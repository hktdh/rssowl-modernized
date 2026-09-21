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

/**
 * Encodes a <code>long</code> as a String that sorts in the same order as the
 * number itself, so that a lexicographic range query over the index behaves
 * like a numeric range query.
 * <p>
 * This replaces Lucene's <code>NumberTools</code>, which was removed. The
 * encoding differs from the one Lucene used (fixed width hex with the sign bit
 * flipped, rather than base 36), which is safe because moving off Lucene 2.3
 * forces the index to be rebuilt anyway. What matters is only that encoding is
 * order preserving and that the same encoder is used when indexing and when
 * querying.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public final class SortableLong {

  /* Flipping the sign bit maps the signed range onto the unsigned one, so that
   * Long.MIN_VALUE encodes to all zeroes and Long.MAX_VALUE to all f. */
  private static final long SIGN_BIT = Long.MIN_VALUE;

  /** The encoding of {@link Long#MIN_VALUE}, the lowest possible term. */
  public static final String MIN_VALUE = toString(Long.MIN_VALUE);

  /** The encoding of {@link Long#MAX_VALUE}, the highest possible term. */
  public static final String MAX_VALUE = toString(Long.MAX_VALUE);

  private SortableLong() {
    // Protect default constructor
  }

  /**
   * @param value the number to encode.
   * @return a 16 character String that sorts in the same order as the number.
   */
  public static String toString(long value) {
    String hex = Long.toHexString(value ^ SIGN_BIT);

    /* Pad to a fixed width, otherwise shorter strings would sort first */
    StringBuilder padded = new StringBuilder(16);
    for (int i = hex.length(); i < 16; i++)
      padded.append('0');

    return padded.append(hex).toString();
  }
}
