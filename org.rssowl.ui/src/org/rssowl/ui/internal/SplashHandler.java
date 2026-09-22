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

package org.rssowl.ui.internal;

import org.eclipse.core.runtime.IProgressMonitor;
import org.eclipse.core.runtime.NullProgressMonitor;
import org.eclipse.osgi.util.NLS;
import org.eclipse.swt.SWT;
import org.eclipse.swt.graphics.Color;
import org.eclipse.swt.graphics.Font;
import org.eclipse.swt.graphics.FontData;
import org.eclipse.swt.graphics.RGB;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.ProgressBar;
import org.eclipse.swt.widgets.Shell;
import org.eclipse.ui.splash.AbstractSplashHandler;
import org.rssowl.ui.internal.util.LayoutUtils;

/**
 * The <code>SplashHandler</code> is reponsible to define the controls that
 * are shown on startup in the Splash-Screen.
 *
 * @author bpasero
 */
public class SplashHandler extends AbstractSplashHandler {
  private Font fVersionFont;
  private Color fVersionColor;
  private ProgressBar fBar;

  /*
   * @see org.eclipse.ui.splash.AbstractSplashHandler#init(org.eclipse.swt.widgets.Shell)
   */
  @Override
  public void init(Shell splash) {
    super.init(splash);

    initResources(splash);
    initComponents(splash);
  }

  private void initResources(Shell splash) {

    /* Font */
    FontData fontData = splash.getDisplay().getSystemFont().getFontData()[0];
    fVersionFont = new Font(splash.getDisplay(), fontData.getName(), 8, SWT.BOLD);

    /* Color */
    fVersionColor = new Color(splash.getDisplay(), new RGB(53, 53, 53));
  }

  private void initComponents(Shell shell) {

    /* Make our composite inherit the splash background */
    shell.setBackgroundMode(SWT.INHERIT_DEFAULT);

    Composite container = new Composite(shell, SWT.NONE);
    container.setLayout(LayoutUtils.createGridLayout(1, 30, 12));
    container.setLocation(0, 240);
    container.setSize(400, 60);

    /* Progress Bar */
    fBar = new ProgressBar(container, SWT.HORIZONTAL);
    fBar.setLayoutData(new GridData(SWT.FILL, SWT.BEGINNING, true, false));
    ((GridData) fBar.getLayoutData()).heightHint = 12;
    fBar.setMaximum(100);
    fBar.setSelection(25);

    /* Version Label */
    Label versionLabel = new Label(container, SWT.NONE);
    versionLabel.setLayoutData(new GridData(SWT.END, SWT.BEGINNING, true, false));
    versionLabel.setFont(fVersionFont);
    versionLabel.setForeground(fVersionColor);
    versionLabel.setText(NLS.bind(Messages.SplashHandler_BUILD, getDisplayVersion()));

    /* Layout All */
    shell.layout(true, true);
  }

  /**
   * The version to show on the splash screen.
   *
   * Read from the bundle rather than written out here: this line used to carry
   * the literal "2.1" and was still saying so long after the bundle had moved
   * on, because a stale string on a splash screen breaks nothing and so nobody
   * notices. The same number now comes from one place, Bundle-Version.
   *
   * @return the version as major.minor.micro, without the OSGi qualifier.
   */
  private static String getDisplayVersion() {
    Object header = Activator.getDefault().getBundle().getHeaders().get("Bundle-Version"); //$NON-NLS-1$
    if (header == null)
      return ""; //$NON-NLS-1$

    /*
     * Bundle-Version is major.minor.micro[.qualifier]. The qualifier is a build
     * stamp ("qualifier" itself while developing), which has no place here.
     */
    String version = header.toString();

    /* Cut at the third dot; no regex, so nothing needs escaping */
    int first = version.indexOf('.');
    int second = (first < 0) ? -1 : version.indexOf('.', first + 1);
    int third = (second < 0) ? -1 : version.indexOf('.', second + 1);

    return (third < 0) ? version : version.substring(0, third);
  }

  /*
   * @see org.eclipse.ui.splash.AbstractSplashHandler#dispose()
   */
  @Override
  public void dispose() {
    super.dispose();
    fVersionColor.dispose();
    fVersionFont.dispose();
  }

  /*
   * @see org.eclipse.ui.splash.AbstractSplashHandler#getBundleProgressMonitor()
   */
  @Override
  public IProgressMonitor getBundleProgressMonitor() {
    return new NullProgressMonitor() {

      @Override
      public void beginTask(String name, final int totalWork) {
        getSplash().getDisplay().syncExec(new Runnable() {
          public void run() {
            fBar.setSelection(50);
          }
        });
      }

      @Override
      public void subTask(String name) {
        getSplash().getDisplay().syncExec(new Runnable() {
          public void run() {
            if (fBar.getSelection() < 100)
              fBar.setSelection(fBar.getSelection() + 8);
          }
        });
      }
    };
  }
}