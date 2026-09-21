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

package org.rssowl.core.internal.persist.search;

import org.apache.lucene.analysis.Analyzer;
import org.apache.lucene.analysis.miscellaneous.ASCIIFoldingFilter;
import org.apache.lucene.queryparser.classic.ParseException;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.Query;
import org.rssowl.core.persist.INews;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * A {@link QueryParser} that strips diacritics from the terms the parser builds
 * on its own.
 * <p>
 * The index is written through an analyzer that folds diacritics, so a search
 * for "tieng" finds "tiếng". Wildcard, prefix, fuzzy and regexp terms never
 * reach that analyzer though: the parser hands them to Lucene as written. That
 * leaves them carrying diacritics the index no longer has, so they match
 * nothing. Typing "Nhà sư" in the feed view is enough to hit this, because the
 * filter appends a wildcard to the last word before searching.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class FoldingQueryParser extends QueryParser {

  /**
   * @param field the default field for query terms.
   * @param analyzer the analyzer used for ordinary terms.
   */
  public FoldingQueryParser(String field, Analyzer analyzer) {
    super(field, analyzer);
  }

  /*
   * The fields whose terms are folded on the way into the index. Everything
   * else is indexed as written apart from being lowercased, so folding a query
   * against those fields would search for terms the index does not hold. Keep
   * this in step with Indexer.createAnalyzer and with the LABEL field in
   * NewsDocument, which folds by hand because it is indexed un-tokenized.
   */
  private static final Set<String> FOLDED_FIELDS = new HashSet<>(Arrays.asList(
      String.valueOf(INews.TITLE),
      String.valueOf(INews.DESCRIPTION),
      String.valueOf(INews.ATTACHMENTS_CONTENT),
      String.valueOf(INews.AUTHOR),
      String.valueOf(INews.CATEGORIES),
      String.valueOf(INews.LABEL)));

  /**
   * @param field the field a term is searched in.
   * @return <code>true</code> if the index holds this field folded, and a
   * query term for it therefore has to be folded too.
   */
  public static boolean foldsField(String field) {
    return FOLDED_FIELDS.contains(field);
  }

  /**
   * Folds a term the same way the indexing analyzer does.
   *
   * @param term the term as the user typed it.
   * @return the term as it would appear in the index.
   */
  public static String fold(String term) {
    if (term == null)
      return null;

    /*
     * Same order as the analyzer: lowercase first, then fold. LowerCaseFilter
     * maps each character on its own, so ask for the same here rather than the
     * default locale: a Turkish locale would otherwise turn 'I' into a dotless
     * 'i' that the index never contains.
     */
    char[] input = term.toLowerCase(Locale.ROOT).toCharArray();

    /* Folding can expand a character into several, so leave room */
    char[] output = new char[input.length * 4];
    int length = ASCIIFoldingFilter.foldToASCII(input, 0, output, 0, input.length);

    return new String(output, 0, length);
  }

  /* Fold only where the index is folded, see FOLDED_FIELDS */
  private static String foldFor(String field, String termStr) {
    return foldsField(field) ? fold(termStr) : termStr;
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getWildcardQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getWildcardQuery(String field, String termStr) throws ParseException {
    return super.getWildcardQuery(field, foldFor(field, termStr));
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getPrefixQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getPrefixQuery(String field, String termStr) throws ParseException {
    return super.getPrefixQuery(field, foldFor(field, termStr));
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getFuzzyQuery(java.lang.String, java.lang.String, float)
   */
  @Override
  protected Query getFuzzyQuery(String field, String termStr, float minSimilarity) throws ParseException {
    return super.getFuzzyQuery(field, foldFor(field, termStr), minSimilarity);
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getRegexpQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getRegexpQuery(String field, String termStr) throws ParseException {
    return super.getRegexpQuery(field, foldFor(field, termStr));
  }
}
