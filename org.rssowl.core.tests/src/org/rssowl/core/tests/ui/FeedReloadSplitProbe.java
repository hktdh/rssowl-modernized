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

import org.eclipse.core.runtime.NullProgressMonitor;
import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.internal.InternalOwl;
import org.rssowl.core.persist.IBookMark;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IFolder;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INews.State;
import org.rssowl.core.persist.ISearchCondition;
import org.rssowl.core.persist.ISearchField;
import org.rssowl.core.persist.SearchSpecifier;
import org.rssowl.core.persist.dao.DynamicDAO;
import org.rssowl.core.persist.reference.FeedLinkReference;
import org.rssowl.core.persist.reference.NewsReference;
import org.rssowl.core.util.SearchHit;

import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.List;

/**
 * Splits what a feed costs on the saving side of a reload into the part the
 * caller waits for and the part Lucene does afterwards.
 * <p>
 * How: inside the test bundle the indexer runs inline, which is why
 * {@link FeedReloadCostProbe} measures both together. Turning
 * {@link InternalOwl#TESTING} off for the duration puts indexing back on its
 * own queue, the way the application runs it, so the two can be timed apart.
 * The index is asked for the news afterwards to find out when it caught up.
 * </p>
 *
 * <pre>
 *   $env:RSSOWL_PROBE_FEEDS = "200"
 *   .\test.ps1 -Classes org.rssowl.core.tests.ui.FeedReloadSplitProbe
 * </pre>
 *
 * @author RSSOwl Development Team
 */
public class FeedReloadSplitProbe {

  private static final int DEFAULT_FEEDS = 200;
  private static final int NEWS_PER_FEED = 20;
  private static final int NEW_PER_RELOAD = 5;

  /* A word carried only by the news of this run, to find them in the index */
  private static final String MARKER = "zzmarkerword"; //$NON-NLS-1$

  /**
   * @throws Exception in case of an error.
   */
  @Test
  public void measure() throws Exception {
    int feedCount = number("RSSOWL_PROBE_FEEDS", DEFAULT_FEEDS); //$NON-NLS-1$

    IModelFactory factory = Owl.getModelFactory();
    IFolder root = factory.createFolder(null, null, "Split"); //$NON-NLS-1$

    /* The feeds as they stand before the reload */
    List<IBookMark> bookmarks = new ArrayList<>(feedCount);
    for (int i = 0; i < feedCount; i++) {
      IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/split/" + i)); //$NON-NLS-1$
      fill(factory, feed, i, 0);
      DynamicDAO.save(feed);

      bookmarks.add(factory.createBookMark(null, root, new FeedLinkReference(feed.getLink()), "Feed " + i)); //$NON-NLS-1$
    }
    DynamicDAO.save(root);

    /* The same feeds as they come back from the network, with news added */
    List<IFeed> downloaded = new ArrayList<>(feedCount);
    for (int i = 0; i < feedCount; i++) {
      IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/split/" + i)); //$NON-NLS-1$
      fill(factory, feed, i, NEW_PER_RELOAD);
      downloaded.add(feed);
    }

    int expected = feedCount * NEW_PER_RELOAD;
    assertEquals(0, countIndexed());

    /* Hand indexing back to its own queue, as in the running application */
    InternalOwl.TESTING = false;
    long foreground;
    long indexed;
    try {
      long start = System.currentTimeMillis();
      for (int i = 0; i < feedCount; i++)
        Owl.getApplicationService().handleFeedReload(bookmarks.get(i), downloaded.get(i), null, false, new NullProgressMonitor());

      foreground = System.currentTimeMillis() - start;

      /* Wait for the index to hold every news this run added */
      long waitStart = System.currentTimeMillis();
      int found = 0;
      while (System.currentTimeMillis() - waitStart < 300000) {
        found = countIndexed();
        if (found >= expected)
          break;

        Thread.sleep(50);
      }

      indexed = System.currentTimeMillis() - start;
      assertEquals("the index did not catch up", expected, found); //$NON-NLS-1$
    } finally {
      InternalOwl.TESTING = true;
    }

    assertTrue(bookmarks.get(0).getNewsCount(INews.State.getVisible()) > 0);

    double perFeed = foreground / (double) feedCount;
    System.out.println("feeds: " + feedCount + ", news added: " + expected); //$NON-NLS-1$ //$NON-NLS-2$
    System.out.println("  caller waits (merge + db4o + retention + counters): " + foreground + "ms, " //$NON-NLS-1$ //$NON-NLS-2$
        + String.format("%.1f", perFeed) + "ms per feed"); //$NON-NLS-1$ //$NON-NLS-2$
    System.out.println("  index caught up at: " + indexed + "ms, " //$NON-NLS-1$ //$NON-NLS-2$
        + String.format("%.1f", indexed / (double) feedCount) + "ms per feed"); //$NON-NLS-1$ //$NON-NLS-2$
    System.out.println("  lucene ran " + (indexed - foreground) + "ms past the last save"); //$NON-NLS-1$ //$NON-NLS-2$
  }

  /* How many news of this run the search index can find */
  private int countIndexed() {
    IModelFactory factory = Owl.getModelFactory();
    ISearchField field = factory.createSearchField(INews.TITLE, INews.class.getName());
    ISearchCondition condition = factory.createSearchCondition(field, SearchSpecifier.IS, MARKER);

    List<SearchHit<NewsReference>> hits = Owl.getPersistenceService().getModelSearch().searchNews(Collections.singletonList(condition), true);

    return hits.size();
  }

  /*
   * The news a feed already holds, plus the ones a reload brings. Only the new
   * ones carry the marker, so the index can be asked about exactly them.
   */
  private void fill(IModelFactory factory, IFeed feed, int feedIndex, int extra) {
    for (int j = 0; j < NEWS_PER_FEED + extra; j++) {
      INews news = factory.createNews(null, feed, new Date(1000L + j));
      news.setTitle("Feed " + feedIndex + " news " + j + (j >= NEWS_PER_FEED ? (" " + MARKER) : "")); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$ //$NON-NLS-4$
      news.setDescription("Body of feed " + feedIndex + " news " + j); //$NON-NLS-1$ //$NON-NLS-2$
      news.setState(State.NEW);

      try {
        news.setLink(new URI("http://127.0.0.1/split/" + feedIndex + "/" + j)); //$NON-NLS-1$ //$NON-NLS-2$
      } catch (Exception e) {
        throw new IllegalStateException(e);
      }
    }
  }

  private int number(String variable, int fallback) {
    String value = System.getenv(variable);
    if (value == null || value.length() == 0)
      return fallback;

    try {
      return Integer.parseInt(value.trim());
    } catch (NumberFormatException e) {
      return fallback;
    }
  }
}
