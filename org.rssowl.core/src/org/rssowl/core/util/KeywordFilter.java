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

package org.rssowl.core.util;

import org.rssowl.core.internal.persist.search.FoldingQueryParser;
import org.rssowl.core.persist.ICategory;
import org.rssowl.core.persist.INews;
import org.rssowl.core.persist.IPerson;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * A list of keywords a news has to carry in order to be shown. A bookmark can
 * be given one, and the feed then only displays the news matching it.
 * <p>
 * Matching is done in memory rather than through the search index on purpose:
 * news arrive in the feed view before they are indexed, and the point of this
 * filter is that the ones that do not match never show up in the first place.
 * The text is folded with {@link FoldingQueryParser#fold(String)} on both
 * sides, which is what the index does too, so a keyword typed without
 * diacritics still matches a news carrying them.
 * </p>
 * <p>
 * A keyword matches a whole word, the same way a search does, and a keyword
 * holding a space matches those words in a row. End it with
 * {@link #WILDCARD} to match longer words as well: "viet*" matches "Vietnam".
 * A news matches when it carries ANY of the keywords, in its title,
 * description, categories or author.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class KeywordFilter {

  /** Separates the keywords inside the stored value */
  public static final String SEPARATOR = ","; //$NON-NLS-1$

  /** Ends a keyword that is to match longer words as well */
  public static final String WILDCARD = "*"; //$NON-NLS-1$

  /* A filter that lets everything through */
  private static final KeywordFilter NONE = new KeywordFilter("", Collections.<String> emptyList()); //$NON-NLS-1$

  private final String fValue;
  private final List<String> fTerms;

  private KeywordFilter(String value, List<String> terms) {
    fValue = value;
    fTerms = terms;
  }

  /**
   * @param value the keywords as the user typed them, separated by
   * {@link #SEPARATOR}, or <code>null</code>.
   * @return a filter for the given keywords, never <code>null</code>. The
   * result is not {@link #isSet()} if the value holds no keyword at all.
   */
  public static KeywordFilter parse(String value) {
    if (!StringUtils.isSet(value))
      return NONE;

    List<String> terms = new ArrayList<>(3);
    StringBuilder normalized = new StringBuilder();
    for (String keyword : value.split(SEPARATOR)) {
      keyword = keyword.trim();
      if (keyword.length() == 0)
        continue;

      String term = foldTerm(keyword);
      if (term.length() == 0 || terms.contains(term)) //Drop empty ones and duplicates that only differ in case or diacritics
        continue;

      if (normalized.length() > 0)
        normalized.append(SEPARATOR).append(' ');
      normalized.append(keyword);
      terms.add(term);
    }

    if (terms.isEmpty())
      return NONE;

    return new KeywordFilter(normalized.toString(), terms);
  }

  /**
   * @return <code>true</code> if this filter holds at least one keyword and
   * therefore filters anything at all.
   */
  public boolean isSet() {
    return !fTerms.isEmpty();
  }

  /**
   * @return the keywords as they are to be stored and shown to the user, or the
   * empty String if this filter is not {@link #isSet()}.
   */
  public String getValue() {
    return fValue;
  }

  /**
   * @return the keywords, folded as they are matched. Never <code>null</code>.
   */
  public List<String> getTerms() {
    return Collections.unmodifiableList(fTerms);
  }

  /**
   * @param news the {@link INews} to match against the keywords.
   * @return <code>true</code> if the given news carries any of the keywords, or
   * if this filter is not {@link #isSet()} at all.
   */
  public boolean matches(INews news) {
    if (!isSet())
      return true;

    if (news == null)
      return false;

    /*
     * The title, the categories and the author are short, the description is
     * not and is HTML on top of it. Fold the cheap ones first and only reach
     * for the description if none of them matched.
     */
    if (containsAnyTerm(foldedHead(news)))
      return true;

    return containsAnyTerm(fold(StringUtils.stripTags(news.getDescription(), true)));
  }

  /* Title, categories and author, folded into one haystack */
  private String foldedHead(INews news) {
    StringBuilder head = new StringBuilder();

    append(head, news.getTitle());

    List<ICategory> categories = news.getCategories();
    for (ICategory category : categories)
      append(head, category.getName());

    IPerson author = news.getAuthor();
    if (author != null) {
      append(head, author.getName());
      if (author.getEmail() != null)
        append(head, author.getEmail().toString());
    }

    return fold(head.toString());
  }

  private void append(StringBuilder builder, String value) {
    if (StringUtils.isSet(value))
      builder.append(value).append(' ');
  }

  private boolean containsAnyTerm(String foldedText) {
    if (foldedText.length() == 0)
      return false;

    for (String term : fTerms) {
      if (containsTerm(foldedText, term))
        return true;
    }

    return false;
  }

  /*
   * A keyword has to match a whole word rather than a part of one. Vietnamese
   * makes this matter far more than English does: folding the diacritics away
   * turns different syllables into the same letters, so "mon" (from "mon")
   * sits inside "mong" (from "mong") and inside "simon", neither of which is
   * the word that was asked for. A trailing wildcard asks for those as well.
   */
  private boolean containsTerm(String foldedText, String term) {
    boolean matchLongerWords = term.endsWith(WILDCARD);
    if (matchLongerWords)
      term = term.substring(0, term.length() - WILDCARD.length());

    int from = 0;
    while (from + term.length() <= foldedText.length()) {
      int at = foldedText.indexOf(term, from);
      if (at < 0)
        return false;

      if (endsWord(foldedText, at - 1) && (matchLongerWords || endsWord(foldedText, at + term.length())))
        return true;

      from = at + 1;
    }

    return false;
  }

  /* Whether the character at the given index stops a word, the ends included */
  private static boolean endsWord(String text, int index) {
    return index < 0 || index >= text.length() || !Character.isLetterOrDigit(text.charAt(index));
  }

  /* A keyword as it is matched: whitespace collapsed, folded, wildcard kept */
  private static String foldTerm(String keyword) {
    boolean matchLongerWords = keyword.endsWith(WILDCARD);
    if (matchLongerWords)
      keyword = keyword.substring(0, keyword.length() - WILDCARD.length());

    String term = fold(keyword);

    return (term.length() > 0 && matchLongerWords) ? term + WILDCARD : term;
  }

  /*
   * Both sides of a match go through here, so that a keyword holding a space
   * still matches a title that wraps across a line break.
   */
  private static String fold(String text) {
    if (!StringUtils.isSet(text))
      return ""; //$NON-NLS-1$

    return FoldingQueryParser.fold(StringUtils.normalizeString(text));
  }

  /*
   * @see java.lang.Object#equals(java.lang.Object)
   */
  @Override
  public boolean equals(Object obj) {
    if (this == obj)
      return true;

    if (!(obj instanceof KeywordFilter))
      return false;

    return fTerms.equals(((KeywordFilter) obj).fTerms);
  }

  /*
   * @see java.lang.Object#hashCode()
   */
  @Override
  public int hashCode() {
    return fTerms.hashCode();
  }

  /*
   * @see java.lang.Object#toString()
   */
  @Override
  public String toString() {
    return super.toString() + " (" + fValue + ")"; //$NON-NLS-1$ //$NON-NLS-2$
  }
}
