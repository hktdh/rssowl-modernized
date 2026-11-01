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
import org.rssowl.core.persist.reference.FeedLinkReference;
import org.rssowl.ui.internal.EntityGroup;
import org.rssowl.ui.internal.editors.feed.NewsColumn;
import org.rssowl.ui.internal.editors.feed.NewsComparator;
import org.rssowl.ui.internal.editors.feed.NewsContentProvider;
import org.rssowl.ui.internal.editors.feed.NewsFilter;
import org.rssowl.ui.internal.editors.feed.NewsGrouping;
import org.rssowl.ui.internal.util.ModelUtils;

import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Date;
import java.util.List;
import java.util.Set;

/**
 * Pins down what the news table shows and in which order.
 * <p>
 * This is the whole of the "what is on screen" decision, and it is deliberately
 * independent of the widget that draws it. The point of testing it on its own
 * is that the table can be moved from a Tree to a Table without anyone having
 * to trust that the list stayed the same: if these pass before and after, the
 * contents did not move.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class NewsVisibleElementsTest {

  private IModelFactory fFactory;
  private IFeed fFeed;

  /**
   * @throws Exception in case of an error.
   */
  @Before
  public void setUp() throws Exception {
    fFactory = Owl.getModelFactory();
    fFeed = fFactory.createFeed(null, new URI("http://www.rssowl.org/visible")); //$NON-NLS-1$
  }

  /* Ungrouped and unsorted: every visible news, order left alone */
  @Test
  public void testUngroupedKeepsEveryVisibleNews() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 500; i++)
      news.add(createNews("Tin " + i, State.NEW, new Date(1000L + i))); //$NON-NLS-1$

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(500, elements.length);
    for (Object element : elements)
      assertTrue(element instanceof INews);
  }

  /*
   * The cap used to live between the cache and the viewer, so a feed with more
   * news than the cap silently lost the rest. Nothing here may shorten the list.
   */
  @Test
  public void testUngroupedDoesNotCapTheList() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 2000; i++)
      news.add(createNews("Tin " + i, State.NEW, new Date(1000L + i))); //$NON-NLS-1$

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(2000, elements.length);
  }

  /* Deleted news are not visible and must never reach the table */
  @Test
  public void testInvisibleNewsAreLeftOut() {
    List<INews> news = new ArrayList<>();
    news.add(createNews("Con lai", State.NEW, new Date(2000L))); //$NON-NLS-1$

    INews deleted = createNews("Da xoa", State.NEW, new Date(3000L)); //$NON-NLS-1$
    deleted.setState(State.DELETED);
    news.add(deleted);

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(1, elements.length);
    assertEquals("Con lai", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
  }

  /* Sorting by date, both directions */
  @Test
  public void testSortOrderIsApplied() {
    List<INews> news = new ArrayList<>();
    news.add(createNews("Giua", State.NEW, new Date(2000L))); //$NON-NLS-1$
    news.add(createNews("Cu nhat", State.NEW, new Date(1000L))); //$NON-NLS-1$
    news.add(createNews("Moi nhat", State.NEW, new Date(3000L))); //$NON-NLS-1$

    NewsComparator ascending = new NewsComparator();
    ascending.setSortBy(NewsColumn.DATE);
    ascending.setAscending(true);

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), ascending, noneCollapsed());
    assertEquals("Cu nhat", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
    assertEquals("Moi nhat", ((INews) elements[2]).getTitle()); //$NON-NLS-1$

    NewsComparator descending = new NewsComparator();
    descending.setSortBy(NewsColumn.DATE);
    descending.setAscending(false);

    elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), descending, noneCollapsed());
    assertEquals("Moi nhat", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
    assertEquals("Cu nhat", ((INews) elements[2]).getTitle()); //$NON-NLS-1$
  }

  /*
   * Grouped: the list is flat, a group header followed by the news it holds.
   * Every news still appears exactly once.
   */
  @Test
  public void testGroupedIsFlatAndKeepsEveryNews() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 40; i++)
      news.add(createNews("Tin " + i, (i % 2 == 0) ? State.NEW : State.READ, new Date(1000L + i))); //$NON-NLS-1$

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.GROUP_BY_STATE), null, noneCollapsed());

    int groups = 0, items = 0;
    for (Object element : elements) {
      if (element instanceof EntityGroup)
        groups++;
      else {
        assertTrue(element instanceof INews);
        items++;
      }
    }

    assertTrue("There must be at least one group", groups > 0); //$NON-NLS-1$
    assertEquals(40, items);
    assertEquals(groups + items, elements.length);

    /* A header always comes before the news it holds */
    assertTrue(elements[0] instanceof EntityGroup);
  }

  /* A collapsed group keeps its header and drops the news under it */
  @Test
  public void testCollapsedGroupHidesItsNews() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 40; i++)
      news.add(createNews("Tin " + i, (i % 2 == 0) ? State.NEW : State.READ, new Date(1000L + i))); //$NON-NLS-1$

    NewsGrouping grouping = grouping(NewsGrouping.Type.GROUP_BY_STATE);
    Object[] expanded = NewsContentProvider.computeVisibleElements(news, filter(), grouping, null, noneCollapsed());

    /* Collapse the first group */
    EntityGroup first = (EntityGroup) expanded[0];
    Set<Long> collapsed = new HashSet<>();
    collapsed.add(Long.valueOf(first.getId()));

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping, null, collapsed);

    assertEquals(expanded.length - first.size(), elements.length);

    /* The header itself stays put, at the front */
    assertTrue(elements[0] instanceof EntityGroup);
    assertEquals(first.getId(), ((EntityGroup) elements[0]).getId());

    /* None of the news it held are left */
    int groupsSeen = 0;
    for (Object element : elements) {
      if (element instanceof EntityGroup)
        groupsSeen++;
    }
    assertEquals(countGroups(expanded), groupsSeen);
  }

  /* Collapsing every group leaves nothing but headers */
  @Test
  public void testCollapsingEveryGroupLeavesOnlyHeaders() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 40; i++)
      news.add(createNews("Tin " + i, (i % 2 == 0) ? State.NEW : State.READ, new Date(1000L + i))); //$NON-NLS-1$

    NewsGrouping grouping = grouping(NewsGrouping.Type.GROUP_BY_STATE);
    Object[] expanded = NewsContentProvider.computeVisibleElements(news, filter(), grouping, null, noneCollapsed());

    Set<Long> collapsed = new HashSet<>();
    for (Object element : expanded) {
      if (element instanceof EntityGroup)
        collapsed.add(Long.valueOf(((EntityGroup) element).getId()));
    }

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping, null, collapsed);

    assertEquals(countGroups(expanded), elements.length);
    for (Object element : elements)
      assertTrue(element instanceof EntityGroup);
  }

  private int countGroups(Object[] elements) {
    int groups = 0;
    for (Object element : elements) {
      if (element instanceof EntityGroup)
        groups++;
    }
    return groups;
  }

  private Set<Long> noneCollapsed() {
    return Collections.emptySet();
  }

  /*
   * Searching inside a feed is a filter, not a different list: the pattern is
   * resolved against the search index once and then every news is asked whether
   * it matched. The list on screen is whatever comes out of here, so if this
   * narrows correctly the feed view narrows correctly.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testTextPatternNarrowsTheList() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/pattern")); //$NON-NLS-1$

    List<INews> news = new ArrayList<>();
    news.add(named(feed, "Chung khoan tang manh")); //$NON-NLS-1$
    news.add(named(feed, "Thoi tiet hom nay")); //$NON-NLS-1$
    news.add(named(feed, "Chung khoan giam nhe")); //$NON-NLS-1$

    /* The pattern is resolved against the index, so the news have to be in it */
    DynamicDAO.save(feed);
    Thread.sleep(1500);

    NewsFilter filter = filter();
    filter.setPattern("khoan"); //$NON-NLS-1$

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(2, elements.length);
    for (Object element : elements)
      assertTrue(((INews) element).getTitle().contains("khoan")); //$NON-NLS-1$

    /* Clearing the pattern brings everything back */
    filter.setPattern(""); //$NON-NLS-1$
    elements = NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());
    assertEquals(3, elements.length);
  }

  /*
   * The keyword filter of a bookmark is not a choice made in this view but a
   * property of the feed: whatever the view is set to, a news that does not
   * carry one of the keywords never reaches the table.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testKeywordFilterOfTheBookmarkNarrowsTheList() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/keyword-filter")); //$NON-NLS-1$

    List<INews> news = new ArrayList<>();
    news.add(named(feed, "Ch\u1EE9ng kho\u00E1n t\u0103ng m\u1EA1nh")); //$NON-NLS-1$
    news.add(named(feed, "Thoi tiet hom nay")); //$NON-NLS-1$
    news.add(named(feed, "Chung khoan giam nhe")); //$NON-NLS-1$

    IBookMark bookmark = bookmarkOn(feed, "chung khoan"); //$NON-NLS-1$

    NewsFilter filter = filter();
    filter.setNewsMark(bookmark);
    assertTrue(filter.isKeywordFilterSet());

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(2, elements.length);
    for (Object element : elements)
      assertTrue(((INews) element).getTitle().toLowerCase().contains("kho")); //$NON-NLS-1$
  }

  /* A bookmark without keywords filters nothing, and says so */
  @Test
  public void testBookmarkWithoutKeywordsShowsEverything() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/no-keyword-filter")); //$NON-NLS-1$

    List<INews> news = new ArrayList<>();
    news.add(named(feed, "Chung khoan tang manh")); //$NON-NLS-1$
    news.add(named(feed, "Thoi tiet hom nay")); //$NON-NLS-1$

    NewsFilter filter = filter();
    filter.setNewsMark(bookmarkOn(feed, null));

    assertFalse(filter.isKeywordFilterSet());
    assertEquals(2, NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed()).length);
  }

  /*
   * The keyword filter and the state filter narrow the list together, neither
   * one replaces the other.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testKeywordFilterAndStateFilterBothApply() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/keyword-and-state")); //$NON-NLS-1$

    List<INews> news = new ArrayList<>();
    /* Matches the keywords and is new */
    news.add(named(feed, "Chung khoan tang manh")); //$NON-NLS-1$

    /* Matches the keywords but is read */
    INews read = named(feed, "Chung khoan giam nhe"); //$NON-NLS-1$
    read.setState(State.READ);
    news.add(read);

    /* New, but does not match the keywords */
    news.add(named(feed, "Thoi tiet hom nay")); //$NON-NLS-1$

    NewsFilter filter = filter();
    filter.setNewsMark(bookmarkOn(feed, "chung khoan")); //$NON-NLS-1$
    filter.setType(NewsFilter.Type.SHOW_NEW);

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed());

    assertEquals(1, elements.length);
    assertEquals("Chung khoan tang manh", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
  }

  /*
   * Changing the keywords in the properties of the bookmark has to reach the
   * open feed view, which it does by asking the filter to re-read them.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testKeywordFilterIsRereadFromTheBookmark() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/keyword-reread")); //$NON-NLS-1$

    List<INews> news = new ArrayList<>();
    news.add(named(feed, "Chung khoan tang manh")); //$NON-NLS-1$
    news.add(named(feed, "Thoi tiet hom nay")); //$NON-NLS-1$

    IBookMark bookmark = bookmarkOn(feed, "chung khoan"); //$NON-NLS-1$

    NewsFilter filter = filter();
    filter.setNewsMark(bookmark);
    assertEquals(1, NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed()).length);

    /* Re-reading without a change must not claim one */
    assertFalse(filter.updateKeywordFilter());

    /* Widen the filter */
    assertTrue(ModelUtils.setKeywordFilter(bookmark, "chung khoan, thoi tiet")); //$NON-NLS-1$
    assertTrue(filter.updateKeywordFilter());
    assertEquals(2, NewsContentProvider.computeVisibleElements(news, filter, grouping(NewsGrouping.Type.NO_GROUPING), null, noneCollapsed()).length);

    /* Drop it altogether */
    assertTrue(ModelUtils.setKeywordFilter(bookmark, null));
    assertTrue(filter.updateKeywordFilter());
    assertFalse(filter.isKeywordFilterSet());
  }

  /*
   * A news the filter judged once is remembered. If the feed edits the news, the
   * verdict has to be reached again rather than taken from that memory.
   *
   * @throws Exception in case of an error.
   */
  @Test
  public void testKeywordVerdictFollowsAnEditedNews() throws Exception {
    IFeed feed = fFactory.createFeed(null, new URI("http://www.rssowl.org/keyword-edited")); //$NON-NLS-1$

    INews item = named(feed, "Thoi tiet hom nay"); //$NON-NLS-1$
    DynamicDAO.save(feed);

    NewsFilter filter = filter();
    filter.setNewsMark(bookmarkOn(feed, "chung khoan")); //$NON-NLS-1$

    assertFalse(filter.isKeywordMatch(item));
    assertFalse("nothing changed yet", filter.keywordMatchChanged(item)); //$NON-NLS-1$

    /* The feed rewrites the headline */
    item.setTitle("Chung khoan tang manh"); //$NON-NLS-1$

    assertTrue(filter.keywordMatchChanged(item));
    assertTrue(filter.isKeywordMatch(item));
  }

  /* A bookmark on the given feed, carrying the given keywords */
  private IBookMark bookmarkOn(IFeed feed, String keywords) {
    DynamicDAO.save(feed);

    IFolder root = fFactory.createFolder(null, null, "Keyword Filters " + feed.getLink()); //$NON-NLS-1$
    IBookMark bookmark = fFactory.createBookMark(null, root, new FeedLinkReference(feed.getLink()), "Feed"); //$NON-NLS-1$
    ModelUtils.setKeywordFilter(bookmark, keywords);
    DynamicDAO.save(root);

    return bookmark;
  }

  private INews named(IFeed feed, String title) {
    INews news = fFactory.createNews(null, feed, new Date());
    news.setTitle(title);
    news.setState(State.NEW);
    return news;
  }

  private NewsFilter filter() {
    NewsFilter filter = new NewsFilter();
    filter.setType(NewsFilter.Type.SHOW_ALL);
    return filter;
  }

  private NewsGrouping grouping(NewsGrouping.Type type) {
    NewsGrouping grouping = new NewsGrouping();
    grouping.setType(type);
    return grouping;
  }

  private INews createNews(String title, State state, Date date) {
    INews news = fFactory.createNews(null, fFeed, date);
    news.setTitle(title);
    news.setState(state);
    return news;
  }
}
