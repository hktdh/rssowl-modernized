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

import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.internal.persist.pref.DefaultPreferences;
import org.rssowl.core.persist.IBookMark;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IFolder;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.INews.State;
import org.rssowl.core.persist.dao.DynamicDAO;
import org.rssowl.core.persist.reference.FeedLinkReference;
import org.rssowl.ui.internal.util.ModelUtils;

import java.net.URI;
import java.util.Date;

/**
 * Builds a profile for looking at the keyword filter of a bookmark in the
 * running application: one bookmark that filters its news by keyword next to
 * one that does not, both inside the same folder.
 * <p>
 * Not a test of anything - it asserts only that it wrote what it meant to - but
 * a fixture that has to run inside the RSSOwl runtime, because only there is
 * there a database to write into. Run it and keep the data directory, then
 * start the application against that directory:
 * </p>
 *
 * <pre>
 *   .\test.ps1 -Classes org.rssowl.core.tests.ui.KeywordFilterSeeder -DataDir D:\...\keywords -KeepData
 *   .\run.ps1 -SkipBuild -DataDir D:\...\keywords
 * </pre>
 *
 * <p>
 * What to look for: the filtered bookmark shows 4 of its 10 news. The two it
 * must leave out even though they read alike once the diacritics are gone are
 * "Qua mong nuoc" and "Simon Says", against the keyword "mon". Each bookmark
 * also holds one sticky news, and only the unfiltered one may be coloured for
 * it: the sticky news of the filtered one is one of the news it hides.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class KeywordFilterSeeder {

  /** The keywords the filtered bookmark is given */
  private static final String KEYWORDS = "chung khoan, vang, mon"; //$NON-NLS-1$

  /**
   * @throws Exception in case of an error.
   */
  @Test
  public void seed() throws Exception {
    IModelFactory factory = Owl.getModelFactory();

    IFolder root = factory.createFolder(null, null, "Tin tuc"); //$NON-NLS-1$

    /* A feed of which only part of the news carry the keywords */
    IFeed filtered = factory.createFeed(null, new URI("http://127.0.0.1/keywords/filtered")); //$NON-NLS-1$
    filtered.setTitle("Bao kinh te"); //$NON-NLS-1$

    /* Written with diacritics: the filter is typed without them */
    news(factory, filtered, "Ch\u1EE9ng kho\u00E1n t\u0103ng m\u1EA1nh phi\u00EAn cu\u1ED1i tu\u1EA7n", "Ch\u1EC9 s\u1ED1 VN-Index v\u01B0\u1EE3t 1300 \u0111i\u1EC3m"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Chung khoan giam nhe dau tuan", "Thanh khoan thap"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Thoi tiet hom nay co mua", "Mien Bac tro lanh"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Ket qua bong da dem qua", "Hai tran cung ket thuc hoa"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Lich chieu phim cuoi tuan", "Gi\u00E1 <b>v\u00E0ng</b> trong b\u00E0i n\u00E0y, khong o tieu de"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Giao thong cua ngo thu do", "Un tac keo dai"); //$NON-NLS-1$ //$NON-NLS-2$

    /* The keyword "mon" matches this one */
    news(factory, filtered, "Món ngon mỗi ngày", "Cach lam ga hap muoi"); //$NON-NLS-1$ //$NON-NLS-2$

    /* Sticky, but hidden by the keywords: the feed must not be coloured for it */
    news(factory, filtered, "Giai bong da hoc sinh toan quoc", "Khai mac cuoi thang").setFlagged(true); //$NON-NLS-1$ //$NON-NLS-2$

    /* And must not match either of these, which only look alike unaccented */
    news(factory, filtered, "Quả mọng nước mùa he", "Dau tay va viet quat"); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, filtered, "Simon Says tro lai man anh", "Phim thieu nhi cuoi nam"); //$NON-NLS-1$ //$NON-NLS-2$

    DynamicDAO.save(filtered);

    /* A feed in the same folder that is not filtered at all */
    IFeed unfiltered = factory.createFeed(null, new URI("http://127.0.0.1/keywords/unfiltered")); //$NON-NLS-1$
    unfiltered.setTitle("Bao the thao"); //$NON-NLS-1$

    news(factory, unfiltered, "Giai ngoai hang vong 12", "Ket qua day du").setFlagged(true); //$NON-NLS-1$ //$NON-NLS-2$
    news(factory, unfiltered, "Chuyen nhuong mua dong", "Nhung ban hop dong dang chu y"); //$NON-NLS-1$ //$NON-NLS-2$

    DynamicDAO.save(unfiltered);

    IBookMark filteredMark = factory.createBookMark(null, root, new FeedLinkReference(filtered.getLink()), "Bao kinh te (loc tu khoa)"); //$NON-NLS-1$
    assertTrue(ModelUtils.setKeywordFilter(filteredMark, KEYWORDS));

    IBookMark unfilteredMark = factory.createBookMark(null, root, new FeedLinkReference(unfiltered.getLink()), "Bao the thao (khong loc)"); //$NON-NLS-1$

    DynamicDAO.save(root);

    /* Open the filtered bookmark on startup, so there is something to look at */
    Owl.getPreferenceService().getEntityScope(filteredMark).putBoolean(DefaultPreferences.BM_OPEN_ON_STARTUP, true);

    assertEquals(10, filtered.getNews().size());
    assertEquals(2, unfiltered.getNews().size());
    assertEquals(KEYWORDS, ModelUtils.getKeywordFilter(filteredMark).getValue());

    System.out.println("Filtered bookmark: '" + filteredMark.getName() + "' keywords '" + KEYWORDS + "' over " + filtered.getNews().size() + " news"); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$ //$NON-NLS-4$
    System.out.println("Unfiltered bookmark: '" + unfilteredMark.getName() + "' over " + unfiltered.getNews().size() + " news"); //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
  }

  private INews news(IModelFactory factory, IFeed feed, String title, String description) {
    INews news = factory.createNews(null, feed, new Date(System.currentTimeMillis() - feed.getNews().size() * 60000L));
    news.setTitle(title);
    news.setDescription(description);
    news.setState(State.NEW);

    return news;
  }
}
