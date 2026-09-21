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

import org.eclipse.jface.viewers.IContentProvider;
import org.eclipse.jface.viewers.TableViewer;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableItem;

/**
 * Shows the headlines of a feed as a flat list.
 * <p>
 * This used to be a Tree, so that grouping could hang news under group rows.
 * The trouble is that the Windows tree control has no virtual mode, so SWT has
 * to insert a real node per row even when nothing is drawn; the list control
 * does have one. Measured on SWT 3.135 with five columns:
 * </p>
 *
 * <pre>
 *   rows     Tree     Table
 *    200    155 ms     26 ms
 *   2000   1209 ms     27 ms
 *  20000  12369 ms     24 ms
 * </pre>
 *
 * <p>
 * That is why a feed used to show only its first two hundred news. Groups are
 * rows of this list rather than parents of other rows - see
 * NewsContentProvider.computeVisibleElements - which costs the tree's folding
 * handles and buys a feed that shows all of itself however big it grows.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class NewsGridViewer extends TableViewer {
  private boolean fBlockRefresh;

  /**
   * @param table the widget to show the headlines in.
   */
  public NewsGridViewer(Table table) {
    super(table);
  }

  /*
   * @see org.eclipse.jface.viewers.StructuredViewer#refresh()
   */
  @Override
  public void refresh() {
    if (fBlockRefresh)
      return;

    /*
     * Ask the content provider to work the list out again first. A lazy Table
     * answers a refresh by re-reading the rows on screen and nothing more: it
     * never asks how many rows there are, so a changed sort order or grouping
     * would redraw the same rows in the same order and look like nothing had
     * happened.
     */
    IContentProvider provider = getContentProvider();
    if (provider instanceof NewsContentProvider)
      ((NewsContentProvider) provider).publishElementCount();

    super.refresh();
  }

  /*
   * Setting a content provider makes JFace refresh straight away, before the
   * label provider and input are in place. Same guard as NewsTableViewer.
   *
   * @see org.eclipse.jface.viewers.ContentViewer#setContentProvider(org.eclipse.jface.viewers.IContentProvider)
   */
  @Override
  public void setContentProvider(IContentProvider provider) {
    fBlockRefresh = true;
    try {
      super.setContentProvider(provider);
    } finally {
      fBlockRefresh = false;
    }
  }

  /*
   * @see org.eclipse.jface.viewers.StructuredViewer#remove(java.lang.Object[])
   */
  @Override
  public void remove(final Object[] elements) {
    /*
     * AbstractTableViewer keeps internalRemove to itself, unlike the tree, so
     * go back through remove() - the override only wraps it in the selection
     * handling, it does not replace it.
     */
    updateSelectionAfterDelete(new Runnable() {
      public void run() {
        NewsGridViewer.super.remove(elements);
      }
    });
  }

  /*
   * A flat list has one level, so the only count that means anything is the
   * number of rows. The element is the input and is ignored.
   *
   * @see setElementCount(java.lang.Object, int)
   */
  public void setElementCount(Object element, int count) {
    setItemCount(count);
  }

  /*
   * @see replaceElement(java.lang.Object, int, java.lang.Object)
   */
  public void replaceElement(Object parent, int index, Object element) {
    replace(element, index);
  }

  /*
   * @see updateElements(java.lang.Object[], java.lang.String[])
   */
  public void updateElements(Object[] elements, String[] properties) {
    update(elements, properties);
  }

  /*
   * @see refreshPreservingPosition(java.lang.Runnable)
   */
  public void refreshPreservingPosition(Runnable refresh) {
    Table table = getTable();
    int topIndex = table.getTopIndex();

    table.setRedraw(false);
    try {
      refresh.run();

      /* The list may have shrunk under us */
      if (topIndex > 0 && topIndex < table.getItemCount())
        table.setTopIndex(topIndex);
    } finally {
      table.setRedraw(true);
    }
  }

  /*
   * Keeps the reader somewhere sensible after rows disappear: select what moved
   * up into the place of the first deleted row, or the last row if the deletion
   * reached the end.
   *
   * @see updateSelectionAfterDelete(java.lang.Runnable)
   */
  public void updateSelectionAfterDelete(Runnable runnable) {
    Table table = getTable();
    int[] oldSelection = table.getSelectionIndices();

    /* Nothing to do, since no selection */
    if (oldSelection.length == 0) {
      runnable.run();
      return;
    }

    int firstSelected = oldSelection[0];
    for (int index : oldSelection)
      firstSelected = Math.min(firstSelected, index);

    table.setRedraw(false);
    try {
      runnable.run();

      int count = table.getItemCount();
      if (count == 0)
        return;

      int target = Math.min(firstSelected, count - 1);
      TableItem item = table.getItem(target);
      if (item != null)
        table.setSelection(target);
    } finally {
      table.setRedraw(true);
    }

    /* Let anyone listening know the selection moved */
    setSelection(getSelection(), true);
  }
}
