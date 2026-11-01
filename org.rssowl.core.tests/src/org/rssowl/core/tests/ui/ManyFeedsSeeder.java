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

import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IFolder;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INews.State;
import org.rssowl.core.persist.dao.DynamicDAO;
import org.rssowl.core.persist.reference.FeedLinkReference;

import java.net.URI;
import java.util.Date;

/**
 * Builds a profile holding a great many feeds, for measuring what the
 * application pays at startup per feed rather than per news.
 * <p>
 * Not a test of anything - it asserts only that it wrote what it meant to. How
 * much it writes is read from the environment, so several sizes can be seeded
 * without touching this file:
 * </p>
 *
 * <pre>
 *   $env:RSSOWL_SEED_FEEDS = "1000"; $env:RSSOWL_SEED_NEWS = "20"
 *   .\test.ps1 -Classes org.rssowl.core.tests.ui.ManyFeedsSeeder -DataDir D:\...\many -KeepData
 *   .\run.ps1 -SkipBuild -DataDir D:\...\many
 * </pre>
 *
 * @author RSSOwl Development Team
 */
public class ManyFeedsSeeder {

  /** How many bookmarks are spread over how many folders */
  private static final int DEFAULT_FEEDS = 500;
  private static final int DEFAULT_NEWS = 20;
  private static final int FEEDS_PER_FOLDER = 25;

  /**
   * @throws Exception in case of an error.
   */
  @Test
  public void seed() throws Exception {
    int feedCount = number("RSSOWL_SEED_FEEDS", DEFAULT_FEEDS); //$NON-NLS-1$
    int newsCount = number("RSSOWL_SEED_NEWS", DEFAULT_NEWS); //$NON-NLS-1$

    IModelFactory factory = Owl.getModelFactory();
    IFolder root = factory.createFolder(null, null, "Feeds"); //$NON-NLS-1$

    long start = System.currentTimeMillis();
    IFolder folder = null;
    for (int i = 0; i < feedCount; i++) {
      if (i % FEEDS_PER_FOLDER == 0)
        folder = factory.createFolder(null, root, "Folder " + (i / FEEDS_PER_FOLDER)); //$NON-NLS-1$

      IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/many/" + i)); //$NON-NLS-1$
      feed.setTitle("Feed " + i); //$NON-NLS-1$

      long now = System.currentTimeMillis();
      for (int j = 0; j < newsCount; j++) {
        INews news = factory.createNews(null, feed, new Date(now - j * 60000L));
        news.setTitle("Feed " + i + " news " + j + " chung khoan thoi tiet bong da"); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
        news.setLink(new URI("http://127.0.0.1/many/" + i + "/" + j)); //$NON-NLS-1$ //$NON-NLS-2$
        news.setDescription("Body of feed " + i + " news " + j); //$NON-NLS-1$ //$NON-NLS-2$

        /* A mix of states, so the unread counters have something to count */
        news.setState((j % 4 == 0) ? State.NEW : ((j % 4 == 1) ? State.UNREAD : State.READ));
      }

      DynamicDAO.save(feed);
      factory.createBookMark(null, folder, new FeedLinkReference(feed.getLink()), "Feed " + i); //$NON-NLS-1$
    }

    DynamicDAO.save(root);

    assertEquals(feedCount / FEEDS_PER_FOLDER, root.getChildren().size());

    System.out.println("Seeded " + feedCount + " feeds x " + newsCount + " news in " + (System.currentTimeMillis() - start) + "ms"); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$ //$NON-NLS-4$
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
