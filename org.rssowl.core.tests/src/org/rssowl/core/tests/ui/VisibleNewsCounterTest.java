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

package org.rssowl.core.tests.ui;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.persist.IBookMark;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IFolder;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INews.State;
import org.rssowl.core.persist.dao.DynamicDAO;
import org.rssowl.core.persist.dao.INewsDAO;
import org.rssowl.core.persist.reference.FeedLinkReference;
import org.rssowl.ui.internal.util.ModelUtils;
import org.rssowl.ui.internal.util.VisibleNewsCounter;

import java.net.URI;
import java.util.Collections;
import java.util.Date;
import java.util.EnumSet;

/**
 * Pins down the number the Bookmarks tree puts next to a feed. A feed that
 * filters its news by keyword has to be counted by what it shows: the number
 * saying 6 while opening the feed produces 3 is the bug this is here for.
 *
 * @author RSSOwl Development Team
 */
public class VisibleNewsCounterTest {

  private IModelFactory fFactory;

  /* Every feed needs a link of its own, and a test may build several */
  private static int fgRun;

  /**
   * @throws Exception in case of an error.
   */
  @Before
  public void setUp() throws Exception {
    fFactory = Owl.getModelFactory();
  }

  /* Without keywords the count is the one the bookmark itself keeps */
  @Test
  public void testUnfilteredBookmarkIsCountedAsBefore() throws Exception {
    IBookMark bookmark = bookmark(null, State.NEW, State.READ, State.UNREAD, State.NEW);

    assertEquals(3, bookmark.getNewsCount(EnumSet.of(State.NEW, State.UNREAD, State.UPDATED)));
    assertEquals(3, VisibleNewsCounter.getUnreadCount(bookmark));
    assertEquals(2, VisibleNewsCounter.getNewCount(bookmark));
    assertTrue(VisibleNewsCounter.hasUnread(bookmark));
  }

  /* With keywords only the news that are shown are counted */
  @Test
  public void testFilteredBookmarkCountsOnlyWhatItShows() throws Exception {
    IBookMark bookmark = bookmark("chung khoan", State.NEW, State.READ, State.UNREAD, State.NEW); //$NON-NLS-1$

    /* Two of the four carry the keyword, and one of those is read */
    assertEquals(3, bookmark.getNewsCount(EnumSet.of(State.NEW, State.UNREAD, State.UPDATED)));
    assertEquals(1, VisibleNewsCounter.getUnreadCount(bookmark));
    assertEquals(1, VisibleNewsCounter.getNewCount(bookmark));
  }

  /* A feed whose unread news are all hidden is not an unread feed */
  @Test
  public void testFeedWithNothingToShowHasNoUnread() throws Exception {
    IBookMark bookmark = bookmark("khong co tin nao", State.NEW, State.READ, State.UNREAD, State.NEW); //$NON-NLS-1$

    assertEquals(0, VisibleNewsCounter.getUnreadCount(bookmark));
    assertEquals(0, VisibleNewsCounter.getNewCount(bookmark));
    assertFalse(VisibleNewsCounter.hasUnread(bookmark));
  }

  /* Reading the one news that was shown takes the count down to nothing */
  @Test
  public void testCountFollowsTheStateOfTheNews() throws Exception {
    IBookMark bookmark = bookmark("chung khoan", State.NEW, State.READ, State.UNREAD, State.NEW); //$NON-NLS-1$
    assertEquals(1, VisibleNewsCounter.getUnreadCount(bookmark));

    /* Mark the matching unread news as read */
    INews shown = null;
    for (INews news : bookmark.getNews(EnumSet.of(State.NEW, State.UNREAD, State.UPDATED))) {
      if (news.getTitle().startsWith("Chung khoan")) //$NON-NLS-1$
        shown = news;
    }
    assertNotNull(shown);

    DynamicDAO.getDAO(INewsDAO.class).setState(Collections.singleton(shown), State.READ, false, false);

    assertEquals(0, VisibleNewsCounter.getUnreadCount(bookmark));
    assertFalse(VisibleNewsCounter.hasUnread(bookmark));
  }

  /* Changing the keywords changes the count, without anything else happening */
  @Test
  public void testCountFollowsTheKeywords() throws Exception {
    IBookMark bookmark = bookmark("chung khoan", State.NEW, State.READ, State.UNREAD, State.NEW); //$NON-NLS-1$
    assertEquals(1, VisibleNewsCounter.getUnreadCount(bookmark));

    /* Widen it to everything the feed holds */
    assertTrue(ModelUtils.setKeywordFilter(bookmark, "chung khoan, thoi tiet, bong da, giao thong")); //$NON-NLS-1$
    assertEquals(3, VisibleNewsCounter.getUnreadCount(bookmark));

    /* And take it away again */
    assertTrue(ModelUtils.setKeywordFilter(bookmark, null));
    assertEquals(3, VisibleNewsCounter.getUnreadCount(bookmark));
    assertEquals(2, VisibleNewsCounter.getNewCount(bookmark));
  }

  /* A feed with nothing marked sticky is not coloured */
  @Test
  public void testFeedWithoutStickyNewsIsNotColoured() throws Exception {
    IBookMark bookmark = bookmark("chung khoan", State.NEW, State.READ, State.UNREAD, State.NEW); //$NON-NLS-1$

    assertEquals(0, bookmark.getStickyNewsCount());
    assertFalse(VisibleNewsCounter.hasSticky(bookmark));
  }

  /*
   * A sticky news the keywords let through colours the feed, one they hide does
   * not. Which news are sticky is looked up in the search index, so the news
   * have to have reached it.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testStickyNewsIsOnlyCountedWhenItIsShown() throws Exception {
    IBookMark shows = bookmarkWithSticky("chung khoan", "Chung khoan tang manh"); //$NON-NLS-1$ //$NON-NLS-2$
    assertEquals(1, shows.getStickyNewsCount());
    assertTrue("the sticky news carries the keyword", VisibleNewsCounter.hasSticky(shows)); //$NON-NLS-1$

    IBookMark hides = bookmarkWithSticky("chung khoan", "Thoi tiet hom nay"); //$NON-NLS-1$ //$NON-NLS-2$
    assertEquals(1, hides.getStickyNewsCount());
    assertFalse("the only sticky news is hidden by the keywords", VisibleNewsCounter.hasSticky(hides)); //$NON-NLS-1$

    IBookMark unfiltered = bookmarkWithSticky(null, "Thoi tiet hom nay"); //$NON-NLS-1$
    assertTrue("without keywords nothing is hidden", VisibleNewsCounter.hasSticky(unfiltered)); //$NON-NLS-1$
  }

  /* As above, with the one news of the feed that is to be sticky */
  private IBookMark bookmarkWithSticky(String keywords, String stickyTitle) throws Exception {
    IBookMark bookmark = bookmark(keywords, State.NEW, State.NEW, State.NEW, State.NEW);

    for (INews news : bookmark.getNews()) {
      if (stickyTitle.equals(news.getTitle())) {
        news.setFlagged(true);
        DynamicDAO.save(news);
      }
    }

    /* The sticky news are looked up through the search index */
    Thread.sleep(1500);

    return bookmark;
  }

  /*
   * Four news in the given states, of which the first two carry "chung khoan".
   * Called with NEW, READ, UNREAD, NEW the bookmark holds three unread news
   * while a filter on that keyword leaves one of them to show.
   */
  private IBookMark bookmark(String keywords, State... states) throws Exception {
    int run = ++fgRun;
    IFeed feed = fFactory.createFeed(null, new URI("http://127.0.0.1/counter/" + run)); //$NON-NLS-1$

    String[] titles = new String[] { "Chung khoan tang manh", "Chung khoan giam nhe", "Thoi tiet hom nay", "Ket qua bong da" }; //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$ //$NON-NLS-4$
    for (int i = 0; i < states.length; i++) {
      INews news = fFactory.createNews(null, feed, new Date(1000L + i));
      news.setTitle(titles[i]);
      news.setState(states[i]);
    }

    DynamicDAO.save(feed);

    IFolder root = fFactory.createFolder(null, null, "Counter " + run); //$NON-NLS-1$
    IBookMark bookmark = fFactory.createBookMark(null, root, new FeedLinkReference(feed.getLink()), "Feed"); //$NON-NLS-1$
    ModelUtils.setKeywordFilter(bookmark, keywords);
    DynamicDAO.save(root);

    return bookmark;
  }
}
