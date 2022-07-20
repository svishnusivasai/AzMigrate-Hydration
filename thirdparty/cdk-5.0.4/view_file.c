#include <cdk_int.h>

/*
 * $Author: vegogine $
 * $Date: 2013/12/24 18:06:02 $
 * $Revision: 1.1 $
 */

/*
 * This allows the user to view a file.
 */
int viewFile (CDKSCREEN *screen,
	      const char *title,
	      const char *filename,
	      CDK_CSTRING2 buttons,
	      int buttonCount)
{
   /* *INDENT-EQLS* */
   int lines            = 0;
   char **info          = 0;
   int result;

   /* Open the file and read the contents. */
   lines = CDKreadFile (filename, &info);

   /* If we couldn't read the file, return an error. */
   if (lines == -1)
   {
      result = lines;
   }
   else
   {

      result = viewInfo (screen, title,
			 (CDK_CSTRING2) info, lines,
			 buttons, buttonCount,
			 TRUE);
      CDKfreeStrings (info);
   }
   return result;
}
