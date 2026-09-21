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
import org.apache.lucene.analysis.LowerCaseFilter;
import org.apache.lucene.analysis.TokenStream;
import org.apache.lucene.analysis.Tokenizer;
import org.apache.lucene.analysis.miscellaneous.ASCIIFoldingFilter;
import org.apache.lucene.analysis.util.CharTokenizer;

/**
 * The <code>LowercaseDelimiterAnalyzer</code> will tokenize the input by the
 * given delimiter char. In addition, all tokens get lowercased and stripped of
 * their diacritics.
 *
 * @author bpasero
 */
public class LowercaseDelimiterAnalyzer extends Analyzer {
  private final char fDelim;

  /**
   * The <code>LowercaseDelimiterAnalyzer</code> will tokenize the input by
   * the given delimiter char. In addition, all tokens get lowercased.
   *
   * @param delim the char that is used to separate tokens.
   */
  public LowercaseDelimiterAnalyzer(char delim) {
    fDelim = delim;
  }

  /*
   * @see org.apache.lucene.analysis.Analyzer#createComponents(java.lang.String)
   */
  @Override
  protected TokenStreamComponents createComponents(String fieldName) {

    /* Split at delim Char. CharTokenizer works on code points now, not chars. */
    Tokenizer source = new CharTokenizer() {

      @Override
      protected boolean isTokenChar(int c) {
        return c != fDelim;
      }
    };

    /* Lowercase */
    TokenStream result = new LowerCaseFilter(source);

    /* Fold diacritics so that a query typed without them still matches */
    result = new ASCIIFoldingFilter(result);

    return new TokenStreamComponents(source, result);
  }
}
