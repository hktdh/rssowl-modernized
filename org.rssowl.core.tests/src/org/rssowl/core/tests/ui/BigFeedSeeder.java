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
import org.rssowl.core.persist.IBookMark;
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
 * Builds a profile holding one bookmark with a great many news, so the news
 * list can be opened at a size no real feed on this machine reaches.
 * <p>
 * Not a test of anything - it asserts only that it wrote what it meant to - but
 * a fixture that has to run inside the RSSOwl runtime, because only there is
 * there a database to write into. Run it and keep the data directory, then
 * start the application against that directory:
 * </p>
 *
 * <pre>
 *   .\test.ps1 -Classes org.rssowl.core.tests.ui.BigFeedSeeder -DataDir D:\...\big -KeepData
 *   .\run.ps1 -SkipBuild -DataDir D:\...\big
 * </pre>
 *
 * @author RSSOwl Development Team
 */
public class BigFeedSeeder {

  /** How many news the bookmark ends up holding */
  private static final int NEWS_COUNT = 20000;

  /**
   * @throws Exception in case of an error.
   */
  @Test
  public void seed() throws Exception {
    IModelFactory factory = Owl.getModelFactory();

    IFolder root = factory.createFolder(null, null, "Feeds"); //$NON-NLS-1$
    IFeed feed = factory.createFeed(null, new URI("http://127.0.0.1/bigfeed")); //$NON-NLS-1$
    feed.setTitle("Feed rat nhieu tin"); //$NON-NLS-1$

    long now = System.currentTimeMillis();
    for (int i = 0; i < NEWS_COUNT; i++) {
      INews news = factory.createNews(null, feed, new Date(now - i * 60000L));
      news.setTitle("Tin thu " + i + " - tieng Viet co dau: chung khoan, dong bac"); //$NON-NLS-1$ //$NON-NLS-2$
      news.setLink(new URI("http://127.0.0.1/bigfeed/" + i)); //$NON-NLS-1$
      news.setDescription("Noi dung cua tin thu " + i); //$NON-NLS-1$

      /* A mix of states, so grouping by state has something to group */
      news.setState((i % 3 == 0) ? State.NEW : State.READ);
    }

    DynamicDAO.save(feed);

    IBookMark mark = factory.createBookMark(null, root, new FeedLinkReference(feed.getLink()), "Feed rat nhieu tin"); //$NON-NLS-1$
    DynamicDAO.save(root);

    assertEquals(NEWS_COUNT, feed.getNews().size());
    System.out.println("Da tao bookmark '" + mark.getName() + "' voi " + NEWS_COUNT + " tin"); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
  }
}
