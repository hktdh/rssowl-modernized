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

package org.rssowl.ui.internal.editors.feed;

/**
 * A content provider that works out how many rows a lazy viewer should show.
 * <p>
 * A lazy {@link org.eclipse.swt.widgets.Table Table} never asks how many rows
 * it has, so refreshing one only re-reads the rows already on screen. Anything
 * that changes the list itself - a different sort order, a search, a grouping -
 * has to push the new count in, or the same rows stay exactly where they were
 * and the refresh looks like it did nothing.
 * </p>
 * <p>
 * Kept as an interface rather than a cast to NewsContentProvider so that the
 * wiring can be tested with a stub, which is the only way to catch a refresh
 * path that forgets to come through here.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public interface ILazyElementCounter {

  /**
   * Works the list out again and tells the viewer how many rows it holds.
   */
  void publishElementCount();
}
