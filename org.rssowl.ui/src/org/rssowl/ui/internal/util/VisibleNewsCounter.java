/*   **********************************************************************  **
 **   Copyright notice                                                       **
 **                                                                          **
 **   (c) 2005-2009 RSSOwl Development Team                                  **
 **   http://www.rssowl.org/                                                 **
 **                                                                          **
 **   All rights reserved                                                    **
 **                                                                          **
 **   This program and the accompanying materials are made available under   **
 **   the terms of the Eclipse Public License v1.0 which accompanies this    **
 **   distribution, and is available at:                                     **
 **   http://www.rssowl.org/legal/epl-v10.html                               **
 **                                                                          **
 **   A copy is found in the file epl-v10.html and important notices to the  **
 **   license from the team is found in the textfile LICENSE.txt distributed **
 **   in this package.                                                       **
 **                                                                          **
 **   This copyright notice MUST APPEAR in all copies of the file!           **
 **                                                                          **
 **   Contributors:                                                          **
 **     RSSOwl Development Team - initial API and implementation             **
 **                                                                          **
 **  **********************************************************************  */

package org.rssowl.ui.internal.util;

import org.rssowl.core.Owl;
import org.rssowl.core.persist.IBookMark;
import org.rssowl.core.persist.IFolderChild;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INewsMark;
import org.rssowl.core.persist.ISearchCondition;
import org.rssowl.core.persist.ISearchField;
import org.rssowl.core.persist.SearchSpecifier;
import org.rssowl.core.persist.reference.NewsReference;
import org.rssowl.core.persist.service.PersistenceException;
import org.rssowl.core.util.KeywordFilter;
import org.rssowl.core.util.SearchHit;
import org.rssowl.ui.internal.Activator;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * How many news of a mark the user actually gets to see. For everything but a
 * bookmark that filters its news by keyword this is the number the mark itself
 * reports; for one that does, the hidden news have to be left out of it, or the
 * feed is shown as holding unread news that opening it does not produce.
 * <p>
 * Counting means asking the keyword filter about each unread news, which is why
 * the answer is remembered per bookmark. It is reached again when the number of
 * unread news changes or the keywords do, and the verdict on a single news is
 * kept across those, so marking one news as read does not re-read the feed.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class VisibleNewsCounter {

  /* The states that make a news count as unread */
  private static final Set<INews.State> UNREAD_STATES = EnumSet.of(INews.State.NEW, INews.State.UNREAD, INews.State.UPDATED);
  private static final Set<INews.State> NEW_STATE = EnumSet.of(INews.State.NEW);

  /* Bookmarks come and go, and nothing here is told when one is deleted */
  private static final int MAX_BOOKMARKS = 256;

  private static final Map<Long, Counts> COUNTS = new ConcurrentHashMap<>();

  /* What was counted for one bookmark, and what it was counted from */
  private static final class Counts {
    private KeywordFilter fFilter;
    private Map<Long, Boolean> fVerdicts = new HashMap<>();
    private int fCountedFrom = -1; //The unfiltered number of unread news
    private int fUnread;
    private int fNew;
    private int fStickyCountedFrom = -1; //The unfiltered number of sticky news
    private boolean fHasSticky;
  }

  /* This utility class constructor is hidden */
  private VisibleNewsCounter() {
    // Protect default constructor
  }

  /**
   * @param mark the {@link INewsMark} to count the unread news of.
   * @return the number of new, unread and updated news the mark shows.
   */
  public static int getUnreadCount(INewsMark mark) {
    Counts counts = countsOf(mark);

    return (counts != null) ? counts.fUnread : mark.getNewsCount(UNREAD_STATES);
  }

  /**
   * @param mark the {@link INewsMark} to count the new news of.
   * @return the number of news the mark shows that are in the NEW state.
   */
  public static int getNewCount(INewsMark mark) {
    Counts counts = countsOf(mark);

    return (counts != null) ? counts.fNew : mark.getNewsCount(NEW_STATE);
  }

  /**
   * @param mark the {@link INewsMark} to ask about.
   * @return <code>true</code> if the mark shows any unread news.
   */
  public static boolean hasUnread(INewsMark mark) {
    return getUnreadCount(mark) > 0;
  }

  /**
   * @param bookmark the {@link IBookMark} to ask about.
   * @return <code>true</code> if the bookmark holds a sticky news that it
   * actually shows. The tree colours a feed by this, so a feed whose only
   * sticky news the keyword filter hides should not be coloured.
   */
  public static boolean hasSticky(IBookMark bookmark) {

    /*
     * The bookmark keeps this number, so the common case - a feed with nothing
     * marked sticky - is answered without reading a single news.
     */
    int stickyCount = bookmark.getStickyNewsCount();
    if (stickyCount == 0)
      return false;

    KeywordFilter filter = ModelUtils.getKeywordFilter(bookmark);
    if (!filter.isSet())
      return true;

    Long id = bookmark.getId();
    if (id == null)
      return true;

    return hasSticky(bookmark, id, filter, stickyCount);
  }

  private static synchronized boolean hasSticky(IBookMark bookmark, Long id, KeywordFilter filter, int stickyCount) {
    Counts counts = entryFor(id);

    if (!filter.equals(counts.fFilter))
      reset(counts, filter);

    if (stickyCount == counts.fStickyCountedFrom)
      return counts.fHasSticky;

    boolean hasSticky = false;
    for (NewsReference ref : stickyNewsOf(bookmark)) {
      INews news = ref.resolve();
      if (news != null && news.isVisible() && news.isFlagged() && filter.matches(news)) {
        hasSticky = true;
        break;
      }
    }

    counts.fHasSticky = hasSticky;
    counts.fStickyCountedFrom = stickyCount;

    return hasSticky;
  }

  /*
   * Which news of a bookmark are sticky is not something the bookmark can say -
   * it keeps a count, not a list - and walking the whole feed to find a handful
   * of them would stall the tree. The index knows, so ask it, and decide about
   * the keywords here as everywhere else. A news flagged a moment ago may not
   * be in the index yet, which delays the colour until the next change.
   */
  private static List<NewsReference> stickyNewsOf(IBookMark bookmark) {
    try {
      IModelFactory factory = Owl.getModelFactory();

      ISearchField locationField = factory.createSearchField(INews.LOCATION, INews.class.getName());
      ISearchCondition inBookmark = factory.createSearchCondition(locationField, SearchSpecifier.IS, ModelUtils.toPrimitive(Collections.singletonList((IFolderChild) bookmark)));

      ISearchField stickyField = factory.createSearchField(INews.IS_FLAGGED, INews.class.getName());
      ISearchCondition isSticky = factory.createSearchCondition(stickyField, SearchSpecifier.IS, Boolean.TRUE);

      List<SearchHit<NewsReference>> hits = Owl.getPersistenceService().getModelSearch().searchNews(Arrays.asList(inBookmark, isSticky), true);

      List<NewsReference> refs = new ArrayList<>(hits.size());
      for (SearchHit<NewsReference> hit : hits)
        refs.add(hit.getResult());

      return refs;
    }

    /* Without the index there is nothing to go on, so colour as before */
    catch (PersistenceException e) {
      Activator.getDefault().logError(e.getMessage(), e);

      return Collections.emptyList();
    }
  }

  /* The counts of a bookmark that filters by keyword, or null for anything else */
  private static Counts countsOf(INewsMark mark) {
    if (!(mark instanceof IBookMark))
      return null;

    IBookMark bookmark = (IBookMark) mark;
    KeywordFilter filter = ModelUtils.getKeywordFilter(bookmark);
    if (!filter.isSet())
      return null;

    Long id = bookmark.getId();
    if (id == null)
      return null;

    return count(bookmark, id, filter);
  }

  private static Counts entryFor(Long id) {
    Counts counts = COUNTS.get(id);
    if (counts == null) {
      if (COUNTS.size() >= MAX_BOOKMARKS)
        COUNTS.clear();

      counts = new Counts();
      COUNTS.put(id, counts);
    }

    return counts;
  }

  /* The keywords changed, so every verdict has to be reached again */
  private static void reset(Counts counts, KeywordFilter filter) {
    counts.fFilter = filter;
    counts.fVerdicts = new HashMap<>();
    counts.fCountedFrom = -1;
    counts.fStickyCountedFrom = -1;
  }

  private static synchronized Counts count(IBookMark bookmark, Long id, KeywordFilter filter) {
    Counts counts = entryFor(id);

    if (!filter.equals(counts.fFilter))
      reset(counts, filter);

    /*
     * The number of unread news is a counter the bookmark keeps, so asking for
     * it is cheap and tells us whether anything can have changed. A news the
     * feed edited into or out of the filter without changing that number is
     * missed until the next change, which is the price of not walking the feed
     * on every repaint of the tree.
     */
    int countedFrom = bookmark.getNewsCount(UNREAD_STATES);
    if (countedFrom == counts.fCountedFrom)
      return counts;

    /*
     * Walk the references rather than the news: they carry the ids without
     * reading the news itself, so only the ones never judged before are read.
     */
    Map<Long, Boolean> previous = counts.fVerdicts;
    Map<Long, Boolean> verdicts = new HashMap<>();

    int unread = 0;
    List<NewsReference> unreadRefs = bookmark.getNewsRefs(UNREAD_STATES);
    for (NewsReference ref : unreadRefs) {
      Long newsId = Long.valueOf(ref.getId());

      Boolean isMatch = previous.get(newsId);
      if (isMatch == null) {
        INews news = ref.resolve();
        isMatch = Boolean.valueOf(news != null && filter.matches(news));
      }

      verdicts.put(newsId, isMatch);
      if (isMatch.booleanValue())
        unread++;
    }

    /* The new news are a part of the unread ones, so their verdicts are in */
    int fresh = 0;
    List<NewsReference> newRefs = bookmark.getNewsRefs(NEW_STATE);
    for (NewsReference ref : newRefs) {
      Boolean isMatch = verdicts.get(Long.valueOf(ref.getId()));
      if (isMatch != null && isMatch.booleanValue())
        fresh++;
    }

    counts.fVerdicts = verdicts; //Only the unread news are kept, so this cannot grow forever
    counts.fUnread = unread;
    counts.fNew = fresh;
    counts.fCountedFrom = countedFrom;

    return counts;
  }
}
