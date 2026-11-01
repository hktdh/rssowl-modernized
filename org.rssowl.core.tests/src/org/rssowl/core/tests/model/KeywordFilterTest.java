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

package org.rssowl.core.tests.model;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;
import org.rssowl.core.Owl;
import org.rssowl.core.persist.ICategory;
import org.rssowl.core.persist.IFeed;
import org.rssowl.core.persist.IModelFactory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.IPerson;
import org.rssowl.core.util.KeywordFilter;

import java.net.URI;
import java.util.Date;

/**
 * Pins down the keyword filter a bookmark can carry: which news it lets
 * through, and that a keyword typed without diacritics still finds a news
 * written with them.
 *
 * @author RSSOwl Development Team
 */
public class KeywordFilterTest {

  private IModelFactory fFactory;
  private IFeed fFeed;

  /**
   * @throws Exception in case of an error.
   */
  @Before
  public void setUp() throws Exception {
    fFactory = Owl.getModelFactory();
    fFeed = fFactory.createFeed(null, new URI("http://www.rssowl.org/keywords")); //$NON-NLS-1$
  }

  /* No keyword means no filtering at all, not an empty feed */
  @Test
  public void testEmptyFilterLetsEverythingThrough() {
    for (String value : new String[] { null, "", "   ", ",", " , , " }) { //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$ //$NON-NLS-4$
      KeywordFilter filter = KeywordFilter.parse(value);

      assertFalse("'" + value + "' holds no keyword", filter.isSet()); //$NON-NLS-1$ //$NON-NLS-2$
      assertTrue(filter.matches(titled("Bat ky tin nao"))); //$NON-NLS-1$
    }
  }

  /* A news matches when it carries ANY of the keywords */
  @Test
  public void testAnyKeywordIsEnough() {
    KeywordFilter filter = KeywordFilter.parse("chung khoan, thoi tiet"); //$NON-NLS-1$

    assertEquals(2, filter.getTerms().size());
    assertTrue(filter.matches(titled("Chung khoan tang manh"))); //$NON-NLS-1$
    assertTrue(filter.matches(titled("Thoi tiet hom nay"))); //$NON-NLS-1$
    assertFalse(filter.matches(titled("Ket qua bong da"))); //$NON-NLS-1$
  }

  /*
   * The whole reason for folding: a feed writes its titles with diacritics, and
   * nobody wants to type them into a filter. Both sides are folded, so it also
   * works the other way around.
   */
  @Test
  public void testDiacriticsAreFoldedOnBothSides() {
    assertTrue(KeywordFilter.parse("chung khoan").matches(titled("Chứng khoán tăng mạnh"))); //$NON-NLS-1$ //$NON-NLS-2$
    assertTrue(KeywordFilter.parse("tiếng việt").matches(titled("Tieng Viet khong dau"))); //$NON-NLS-1$ //$NON-NLS-2$
    assertTrue(KeywordFilter.parse("CHỨNG KHOÁN").matches(titled("chung khoan"))); //$NON-NLS-1$ //$NON-NLS-2$
    assertFalse(KeywordFilter.parse("chung khoan").matches(titled("Thị trường vàng"))); //$NON-NLS-1$ //$NON-NLS-2$
  }

  /*
   * Reported from a Vietnamese feed: filtering on "mon" also brought in "mong"
   * and "simon". Folding the diacritics away makes different syllables look
   * alike, so a keyword that matched part of a word was wrong far more often
   * than it was useful. A keyword matches a whole word.
   */
  @Test
  public void testKeywordDoesNotMatchPartOfAWord() {
    KeywordFilter filter = KeywordFilter.parse("m\u00F3n"); //$NON-NLS-1$

    /* The word itself, written with and without its diacritics */
    assertTrue(filter.matches(titled("M\u00F3n ngon m\u1ED7i ng\u00E0y"))); //$NON-NLS-1$
    assertTrue(filter.matches(titled("Mon an ba mien"))); //$NON-NLS-1$

    /* Other words that only look alike once the diacritics are gone */
    assertFalse(filter.matches(titled("Qu\u1EA3 m\u1ECDng n\u01B0\u1EDBc"))); //$NON-NLS-1$
    assertFalse(filter.matches(titled("Mong manh"))); //$NON-NLS-1$
    assertFalse(filter.matches(titled("Simon Says"))); //$NON-NLS-1$
  }

  /* Punctuation around a word leaves it a word */
  @Test
  public void testPunctuationStillEndsAWord() {
    KeywordFilter filter = KeywordFilter.parse("mon"); //$NON-NLS-1$

    assertTrue(filter.matches(titled("Am thuc: \"mon\", va hon the"))); //$NON-NLS-1$
    assertTrue(filter.matches(titled("Mon."))); //$NON-NLS-1$
  }

  /* A trailing wildcard asks for the longer words as well, at the end only */
  @Test
  public void testTrailingWildcardMatchesLongerWords() {
    KeywordFilter filter = KeywordFilter.parse("viet*"); //$NON-NLS-1$

    assertTrue(filter.matches(titled("Vietnam Airlines"))); //$NON-NLS-1$
    assertTrue(filter.matches(titled("Viet Nam"))); //$NON-NLS-1$
    assertFalse("the wildcard widens the end of the keyword, not its start", filter.matches(titled("Soviet Union"))); //$NON-NLS-1$ //$NON-NLS-2$

    /* Without it, the longer word is not asked for */
    assertFalse(KeywordFilter.parse("viet").matches(titled("Vietnam Airlines"))); //$NON-NLS-1$ //$NON-NLS-2$
  }

  /* A keyword of several words matches them in a row, however they are spaced */
  @Test
  public void testPhraseMatchesAcrossWhitespace() {
    INews news = titled("Khong lien quan"); //$NON-NLS-1$
    news.setDescription("<p>Chung\n   khoan\ttang manh</p>"); //$NON-NLS-1$

    assertTrue(KeywordFilter.parse("chung khoan").matches(news)); //$NON-NLS-1$
    assertFalse(KeywordFilter.parse("khoan chung").matches(news)); //$NON-NLS-1$
  }

  /* The description is matched too, but as text: its markup is not keyword material */
  @Test
  public void testDescriptionIsMatchedWithoutItsMarkup() {
    INews news = titled("Khong lien quan"); //$NON-NLS-1$
    news.setDescription("<p>Gia <b>vang</b> hom nay</p>"); //$NON-NLS-1$

    assertTrue(KeywordFilter.parse("vang").matches(news)); //$NON-NLS-1$
    assertTrue(KeywordFilter.parse("gia vang").matches(news)); //$NON-NLS-1$

    INews linked = titled("Khong lien quan"); //$NON-NLS-1$
    linked.setDescription("<a href=\"http://example.org/vang\">Doc tiep</a>"); //$NON-NLS-1$

    assertFalse("a tag name is not part of the news", KeywordFilter.parse("href").matches(linked)); //$NON-NLS-1$ //$NON-NLS-2$
    assertTrue(KeywordFilter.parse("doc tiep").matches(linked)); //$NON-NLS-1$
  }

  /* Categories and the author count as well, the same way a search covers them */
  @Test
  public void testCategoriesAndAuthorAreMatched() {
    INews news = titled("Khong lien quan"); //$NON-NLS-1$

    ICategory category = fFactory.createCategory(null, news);
    category.setName("Chứng khoán"); //$NON-NLS-1$

    IPerson author = fFactory.createPerson(null, news);
    author.setName("Nguyen Van A"); //$NON-NLS-1$

    assertTrue(KeywordFilter.parse("chung khoan").matches(news)); //$NON-NLS-1$
    assertTrue(KeywordFilter.parse("nguyen van a").matches(news)); //$NON-NLS-1$
  }

  /* What is stored back is tidied up, and keywords that fold alike are one keyword */
  @Test
  public void testValueIsNormalizedAndDuplicatesDropped() {
    KeywordFilter filter = KeywordFilter.parse("  chung khoan ,, Chứng khoán ,vang  "); //$NON-NLS-1$

    assertEquals(2, filter.getTerms().size());
    assertEquals("chung khoan, vang", filter.getValue()); //$NON-NLS-1$
  }

  /* A news with nothing in it cannot carry a keyword */
  @Test
  public void testEmptyNewsNeverMatches() {
    assertFalse(KeywordFilter.parse("vang").matches(fFactory.createNews(null, fFeed, new Date()))); //$NON-NLS-1$
  }

  private INews titled(String title) {
    INews news = fFactory.createNews(null, fFeed, new Date());
    news.setTitle(title);
    return news;
  }
}
