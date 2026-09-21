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

  /**
   * Folds a term the same way the indexing analyzer does.
   *
   * @param term the term as the user typed it.
   * @return the term as it would appear in the index.
   */
  public static String fold(String term) {
    if (term == null)
      return null;

    /* Same order as the analyzer: lowercase first, then fold */
    char[] input = term.toLowerCase().toCharArray();

    /* Folding can expand a character into several, so leave room */
    char[] output = new char[input.length * 4];
    int length = ASCIIFoldingFilter.foldToASCII(input, 0, output, 0, input.length);

    return new String(output, 0, length);
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getWildcardQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getWildcardQuery(String field, String termStr) throws ParseException {
    return super.getWildcardQuery(field, fold(termStr));
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getPrefixQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getPrefixQuery(String field, String termStr) throws ParseException {
    return super.getPrefixQuery(field, fold(termStr));
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getFuzzyQuery(java.lang.String, java.lang.String, float)
   */
  @Override
  protected Query getFuzzyQuery(String field, String termStr, float minSimilarity) throws ParseException {
    return super.getFuzzyQuery(field, fold(termStr), minSimilarity);
  }

  /*
   * @see org.apache.lucene.queryparser.classic.QueryParserBase#getRegexpQuery(java.lang.String, java.lang.String)
   */
  @Override
  protected Query getRegexpQuery(String field, String termStr) throws ParseException {
    return super.getRegexpQuery(field, fold(termStr));
  }
}
