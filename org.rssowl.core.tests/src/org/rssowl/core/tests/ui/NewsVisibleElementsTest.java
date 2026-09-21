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
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INews.State;
import org.rssowl.ui.internal.EntityGroup;
import org.rssowl.ui.internal.editors.feed.NewsColumn;
import org.rssowl.ui.internal.editors.feed.NewsComparator;
import org.rssowl.ui.internal.editors.feed.NewsContentProvider;
import org.rssowl.ui.internal.editors.feed.NewsFilter;
import org.rssowl.ui.internal.editors.feed.NewsGrouping;

import java.net.URI;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

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

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null);

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

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null);

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

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), null);

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

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), ascending);
    assertEquals("Cu nhat", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
    assertEquals("Moi nhat", ((INews) elements[2]).getTitle()); //$NON-NLS-1$

    NewsComparator descending = new NewsComparator();
    descending.setSortBy(NewsColumn.DATE);
    descending.setAscending(false);

    elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.NO_GROUPING), descending);
    assertEquals("Moi nhat", ((INews) elements[0]).getTitle()); //$NON-NLS-1$
    assertEquals("Cu nhat", ((INews) elements[2]).getTitle()); //$NON-NLS-1$
  }

  /* Grouped: the elements are groups, and they carry every news between them */
  @Test
  public void testGroupedReturnsGroupsHoldingEveryNews() {
    List<INews> news = new ArrayList<>();
    for (int i = 0; i < 40; i++)
      news.add(createNews("Tin " + i, (i % 2 == 0) ? State.NEW : State.READ, new Date(1000L + i))); //$NON-NLS-1$

    Object[] elements = NewsContentProvider.computeVisibleElements(news, filter(), grouping(NewsGrouping.Type.GROUP_BY_STATE), null);

    assertTrue("Phai co it nhat mot nhom", elements.length > 0); //$NON-NLS-1$

    int inGroups = 0;
    for (Object element : elements) {
      assertTrue(element instanceof EntityGroup);
      inGroups += ((EntityGroup) element).size();
    }

    assertEquals(40, inGroups);
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
