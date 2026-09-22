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

import org.eclipse.jface.viewers.ILazyContentProvider;
import org.eclipse.jface.viewers.Viewer;
import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.swt.widgets.Table;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.rssowl.ui.internal.editors.feed.ILazyElementCounter;
import org.rssowl.ui.internal.editors.feed.NewsGridViewer;

/**
 * Every way of refreshing the news list must reach the content provider.
 * <p>
 * A lazy Table re-reads the rows already on screen when refreshed and never
 * asks how many rows it now has, so anything that changes the list itself has
 * to push the new count in. Two bugs came from missing exactly this: sorting by
 * clicking a column header, and searching inside a feed, both went through
 * refresh(boolean) while only the no-argument refresh had been wired up. The
 * sorter and the filter were updated correctly; the same rows simply stayed on
 * screen in the same order, with nothing in the log.
 * </p>
 * <p>
 * These are wiring tests rather than behaviour tests, which is the point: the
 * behaviour is covered by NewsVisibleElementsTest, and what broke was the
 * connection between the two.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class NewsGridViewerRefreshTest {

  /* Stands in for NewsContentProvider, counting what it was asked to do */
  private static class CountingProvider implements ILazyContentProvider, ILazyElementCounter {
    int published;
    NewsGridViewer viewer;
    int rows;

    public void publishElementCount() {
      published++;
      if (viewer != null)
        viewer.setElementCount(null, rows);
    }

    public void updateElement(int index) {}

    public void dispose() {}

    public void inputChanged(Viewer v, Object oldInput, Object newInput) {}
  }

  private Display fDisplay;
  private boolean fOwnsDisplay;
  private Shell fShell;
  private NewsGridViewer fViewer;
  private CountingProvider fProvider;

  /**
   * @throws Exception in case of an error.
   */
  @Before
  public void setUp() throws Exception {
    fDisplay = Display.getCurrent();
    if (fDisplay == null) {
      fDisplay = new Display();
      fOwnsDisplay = true;
    }

    fShell = new Shell(fDisplay);
    fShell.setSize(600, 400);

    Table table = new Table(fShell, SWT.MULTI | SWT.FULL_SELECTION | SWT.VIRTUAL);
    fViewer = new NewsGridViewer(table);

    fProvider = new CountingProvider();
    fProvider.viewer = fViewer;
    fProvider.rows = 25;

    fViewer.setContentProvider(fProvider);
    fViewer.setInput(new Object());

    /* Whatever happened while wiring up is not what is under test */
    fProvider.published = 0;
  }

  /**
   * @throws Exception in case of an error.
   */
  @After
  public void tearDown() throws Exception {
    if (fShell != null && !fShell.isDisposed())
      fShell.dispose();
    if (fOwnsDisplay && fDisplay != null && !fDisplay.isDisposed())
      fDisplay.dispose();
  }

  /* The no-argument refresh: the only one that used to be wired up */
  @Test
  public void testPlainRefreshPublishesTheCount() {
    fViewer.refresh();
    assertTrue("refresh() must publish the row count", fProvider.published > 0); //$NON-NLS-1$
  }

  /* What clicking a column header calls */
  @Test
  public void testRefreshWithUpdateLabelsPublishesTheCount() {
    fProvider.published = 0;
    fViewer.refresh(false);
    assertTrue("refresh(false) must publish the row count", fProvider.published > 0); //$NON-NLS-1$

    fProvider.published = 0;
    fViewer.refresh(true);
    assertTrue("refresh(true) must publish the row count", fProvider.published > 0); //$NON-NLS-1$
  }

  /* What FeedView.refreshTableViewer calls, by way of the filter bar */
  @Test
  public void testRefreshOfAnElementPublishesTheCount() {
    fProvider.published = 0;
    fViewer.refresh(fViewer.getInput());
    assertTrue("refresh(element) must publish the row count", fProvider.published > 0); //$NON-NLS-1$

    fProvider.published = 0;
    fViewer.refresh(fViewer.getInput(), true);
    assertTrue("refresh(element, true) must publish the row count", fProvider.published > 0); //$NON-NLS-1$
  }

  /* A refresh has to end with the widget showing the new number of rows */
  @Test
  public void testRowCountFollowsTheProvider() {
    fProvider.rows = 25;
    fViewer.refresh(false);
    assertEquals(25, fViewer.getTable().getItemCount());

    /* The kind of change a search makes: far fewer rows */
    fProvider.rows = 3;
    fViewer.refresh(false);
    assertEquals(3, fViewer.getTable().getItemCount());

    /* And clearing the search puts them back */
    fProvider.rows = 25;
    fViewer.refresh(true);
    assertEquals(25, fViewer.getTable().getItemCount());
  }
}
