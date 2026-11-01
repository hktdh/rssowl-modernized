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

import static org.junit.Assert.assertTrue;

import org.eclipse.core.runtime.NullProgressMonitor;
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

import java.net.URI;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * Measures what one feed costs on the saving side of a reload, which is the
 * step the application runs one at a time no matter how many feeds are being
 * downloaded in parallel.
 * <p>
 * Not a test of behaviour: it only asserts that the work happened at all and
 * prints the timings. Run it on its own and read the numbers:
 * </p>
 *
 * <pre>
 *   $env:RSSOWL_PROBE_FEEDS = "200"
 *   .\test.ps1 -Classes org.rssowl.core.tests.ui.FeedReloadCostProbe
 * </pre>
 *
 * @author RSSOwl Development Team
 */
public class FeedReloadCostProbe {

  private static final int DEFAULT_FEEDS = 200;
  private static final int NEWS_PER_FEED = 20;

  /**
   * @throws Exception in case of an error.
   */
  @Test
  public void measure() throws Exception {
    int feedCount = number("RSSOWL_PROBE_FEEDS", DEFAULT_FEEDS); //$NON-NLS-1$

    IModelFactory factory = Owl.getModelFactory();
    IFolder root = factory.createFolder(null, null, "Probe"); //$NON-NLS-1$

    /* Build the bookmarks first, each over a feed that already holds news */
    List<IBookMark> bookmarks = new ArrayList<>(feedCount);
    for (int i = 0; i < feedCount; i++) {
      IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/probe/" + i)); //$NON-NLS-1$
      fill(factory, feed, i, 0);
      DynamicDAO.save(feed);

      bookmarks.add(factory.createBookMark(null, root, new FeedLinkReference(feed.getLink()), "Feed " + i)); //$NON-NLS-1$
    }
    DynamicDAO.save(root);

    /*
     * Now hand each bookmark a freshly downloaded feed holding the same news
     * plus five new ones, which is what a reload of a live feed looks like.
     */
    List<IFeed> downloaded = new ArrayList<>(feedCount);
    for (int i = 0; i < feedCount; i++) {
      IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/probe/" + i)); //$NON-NLS-1$
      fill(factory, feed, i, 5);
      downloaded.add(feed);
    }

    long start = System.currentTimeMillis();
    for (int i = 0; i < feedCount; i++)
      Owl.getApplicationService().handleFeedReload(bookmarks.get(i), downloaded.get(i), null, false, new NullProgressMonitor());

    long elapsed = System.currentTimeMillis() - start;

    assertTrue(bookmarks.get(0).getNewsCount(INews.State.getVisible()) > 0);

    System.out.println("handleFeedReload: " + feedCount + " feeds in " + elapsed + "ms, " //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
        + String.format("%.1f", (elapsed / (double) feedCount)) + "ms per feed"); //$NON-NLS-1$ //$NON-NLS-2$
    System.out.println("  at that rate one pass over 1000 feeds costs " //$NON-NLS-1$
        + String.format("%.1f", (elapsed / (double) feedCount) * 1000 / 1000) + "s of saving alone"); //$NON-NLS-1$ //$NON-NLS-2$
  }

  /* The same news every time, plus a few that are new since the last reload */
  private void fill(IModelFactory factory, IFeed feed, int feedIndex, int extra) {
    for (int j = 0; j < NEWS_PER_FEED + extra; j++) {
      INews news = factory.createNews(null, feed, new Date(1000L + j));
      news.setTitle("Feed " + feedIndex + " news " + j); //$NON-NLS-1$ //$NON-NLS-2$
      news.setDescription("Body of feed " + feedIndex + " news " + j); //$NON-NLS-1$ //$NON-NLS-2$
      news.setState(State.NEW);

      try {
        news.setLink(new URI("http://127.0.0.1/probe/" + feedIndex + "/" + j)); //$NON-NLS-1$ //$NON-NLS-2$
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
