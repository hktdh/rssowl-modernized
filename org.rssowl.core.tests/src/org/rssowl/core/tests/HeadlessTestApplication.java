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

package org.rssowl.core.tests;

import org.eclipse.equinox.app.IApplication;
import org.eclipse.equinox.app.IApplicationContext;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

import java.util.ArrayList;
import java.util.List;

/**
 * Runs JUnit test classes inside a real RSSOwl runtime, without an IDE.
 * <p>
 * The tests here are plug-in tests: they reach for {@code Owl.getModelFactory()}
 * and the persistence service, so they only mean anything with the OSGi runtime
 * up. PDE can run them, but it drives them from the IDE over a socket, which is
 * no use from a script. This application does the same job by calling JUnit
 * directly and reporting on stdout, so a build can gate on the exit code.
 * </p>
 *
 * @author RSSOwl Development Team
 */
public class HeadlessTestApplication implements IApplication {

  /*
   * @see org.eclipse.equinox.app.IApplication#start(org.eclipse.equinox.app.IApplicationContext)
   */
  public Object start(IApplicationContext context) {
    String[] args = (String[]) context.getArguments().get(IApplicationContext.APPLICATION_ARGS);

    List<Class<?>> classes = new ArrayList<>();
    List<String> unknown = new ArrayList<>();
    if (args != null) {
      for (String arg : args) {
        if (arg == null || arg.length() == 0 || arg.charAt(0) == '-')
          continue;

        try {
          classes.add(Class.forName(arg));
        } catch (ClassNotFoundException e) {
          unknown.add(arg);
        }
      }
    }

    if (!unknown.isEmpty()) {
      System.out.println("Khong tim thay lop test: " + unknown); //$NON-NLS-1$
      return Integer.valueOf(2);
    }

    if (classes.isEmpty()) {
      System.out.println("Cach dung: -application org.rssowl.core.tests.headless <lop test> [<lop test> ...]"); //$NON-NLS-1$
      return Integer.valueOf(2);
    }

    System.out.println("Chay " + classes.size() + " lop test"); //$NON-NLS-1$ //$NON-NLS-2$
    System.out.println();

    Result result = JUnitCore.runClasses(classes.toArray(new Class<?>[classes.size()]));

    for (Failure failure : result.getFailures()) {
      System.out.println("SAI  " + failure.getTestHeader()); //$NON-NLS-1$
      System.out.println(failure.getTrace());
      System.out.println();
    }

    System.out.println(String.format("Chay %d, sai %d, bo qua %d, %d ms", //$NON-NLS-1$
        Integer.valueOf(result.getRunCount()), Integer.valueOf(result.getFailureCount()),
        Integer.valueOf(result.getIgnoreCount()), Long.valueOf(result.getRunTime())));
    System.out.println(result.wasSuccessful() ? "TAT CA DUNG" : "CO TEST SAI"); //$NON-NLS-1$ //$NON-NLS-2$

    return result.wasSuccessful() ? IApplication.EXIT_OK : Integer.valueOf(1);
  }

  /*
   * @see org.eclipse.equinox.app.IApplication#stop()
   */
  public void stop() {}
}
