/*
 * Main program that controls the translation of Icon programs.
 */

#include "itran.h"
#include "sym.h"
#include "tree.h"
#include "token.h"

#define MAXFILES 64		/* maximum number of file names */
#define MAXNAME  40		/* maximum length of file name */

int fatalerrs	= 0;		/* total number of fatal errors */
int warnings	= 0;		/* total number of warnings */
int nocode	= 0;		/* non-zero to suppress code generation */
int inline	= 1;		/* current input line number */
int incol	= 0;		/* current input column number */
int peekc	= 0;		/* one-character look ahead */
int implicit	= LOCAL;	/* implicit scope for undeclared identifiers */
int silence	= 0;		/* don't be silent (default) */
int trace	= 0;		/* initial setting of &trace */

FILE *infile;			/* current input file */
FILE *codefile; 		/* current ucode output file */
FILE *globfile; 		/* current global table output file */
char inbuf[BUFSIZ];		/* buffers for above files */
char codebuf[BUFSIZ];		/*   to avoid automatic */
char globbuf[BUFSIZ];		/*   allocation by i/o system */
char codename[MAXNAME]; 	/* name of ucode output file */
char globname[MAXNAME]; 	/* name of global table output file */

char *filelist[MAXFILES];	/* list of input file names */
char **filep;			/* pointer to current input file name */

main(argc,argv)
int argc;
char **argv;
   {
   int aval;
   int mflag = 0;		/* m4 preprocessed */
   char *progname;
   static char mname[80];	/* m4 command string */
   register char **fp;		/* indexes filelist while scanning args */
   char *maknam();
   extern FILE *popen();

   progname = argv[0];
   filep = fp = filelist;
   while (--argc) {
      if (**++argv == '-') {	/* argument starts with a '-' */
         switch ((*argv)[1]) {
            case '\0':		/* read standard input */
               *fp++ = *argv;
               continue;
            case 'm':		/* process with m4 */
                mflag++;
                continue;
            case 'u':		/* tell ilink to note undeclared identifiers*/
                implicit = 0;
                continue;
            case 't':		/* tell ilink to turn on tracing */
                trace++;
                continue;
            case 's':		/* don't produce informative messages */
                silence++;
                continue;
            case 'D':		/* debug flag for ilink, ignored by itran */
                continue;
            case 'S':
               if ((*argv)[3] == 'h') { /* change hash table size */
                  aval = atoi(&(*argv)[4]);
                  if (aval <= 0)
                     goto badarg;
                  switch ((*argv)[2]) {
                     case 'i': ihsize = aval; continue;
                     case 'g': ghsize = aval; continue;
                     case 'c': chsize = aval; continue;
                     case 'l': lhsize = aval; continue;
                     case 'f': continue;
                     }
                  }
               else {			/* change symbol table size */
                  aval = atoi(&(*argv)[3]);
                  if (aval <= 0)
                     goto badarg;
                  switch ((*argv)[2]) {
                     case 'c': csize = aval; continue;
                     case 'i': isize = aval; continue;
                     case 'g': gsize = aval; continue;
                     case 'l': lsize = aval; continue;
                     case 's': ssize = aval; continue;
                     case 't': tsize = aval; continue;
                     case 'f': continue;
                     case 'r': continue;
                     case 'L': continue;
                     case 'C': continue;
                     }
                  }
            default:
            badarg:
               fprintf(stderr, "bad argument: %s\n", *argv);
               continue;
            }
         }
      else	/* argument doesn't start with a '-', assume it's a file */
         *fp++ = *argv;
      }
   *fp++ = 0;	/* terminate list of files with a NULL */
   /*
    * Process each input file in turn.	If m4 processing is to be done (mflag
    *  is set), a pipe is opened to m4 with the current file name, otherwise,
    *  the input file is opened.  infile is the file pointer for the current
    *  input file and filep is the name of the file.
    */
   for ( ; *filep; filep++) {
      inline = 1;
      if (!mflag) {
         if (*filep[0] == '-')
            infile = stdin;
         else
            infile = fopen(*filep, "r");
         }
      else {
         strcpy(mname, "m4 ");
         strcat(mname, *filep);
         infile = popen(mname, "r");
         }
      if (*filep[0] == '-')
         *filep = "stdin";
      if (infile == NULL) {
         fprintf(stderr, "%s: cannot open %s\n", progname, *filep);
         fatalerrs++;
         continue;
         }
      setbuf(infile, inbuf);

      if (!silence)
         fprintf(stderr, "%s:\n", *filep);

      /*
       * Form names for the .u1 and .u2 files and open them.
       */
      maknam(codename, *filep, ".u1");
      maknam(globname, *filep, ".u2");
      codefile = fopen(codename, "w");
      if (codefile == NULL) {
         fprintf(stderr, "%s: cannot create %s\n", progname, codename);
         fatalerrs++;
         continue;
         }
      setbuf(codefile, codebuf);
      globfile = fopen(globname, "w");
      if (globfile == NULL) {
         fprintf(stderr, "%s: cannot create %s\n", progname, globname);
         fatalerrs++;
         continue;
         }
      setbuf(globfile, globbuf);

      meminit();	/* Initialize data structures */

      yyparse();	/* Parse the input */

      /*
       * Close the input file and the .u1 and .u2 files.
       */
      if (!mflag)
         fclose(infile);
      else {
         if (pclose(infile) != 0) {
            fprintf(stderr, "%s: m4 terminated abnormally\n", progname);
            fatalerrs++;
            }
         }
      fclose(codefile);
      fclose(globfile);
      }

   /*
    * Produce information about errors and warnings and be correct about it.
    */
   if (fatalerrs == 1)
      fprintf(stderr, "1 error; ");
   else if (fatalerrs > 1)
      fprintf(stderr, "%d errors; ", fatalerrs);
   else if (!silence)
      fprintf(stderr, "No errors; ");
   if (warnings == 1)
      fprintf(stderr, "1 warning\n");
   else if (warnings > 1)
      fprintf(stderr, "%d warnings\n", warnings);
   else if (!silence)
      fprintf(stderr, "no warnings\n");
   else if (fatalerrs > 0)
      fprintf(stderr, "\n");
   if (fatalerrs > 0)
      exit(1);
   exit(0);
   }

/*
 * maknam - makes a file name from prefix and suffix.
 *
 * Uses only the last file specification if name is a path,
 * replaces suffix of name with suffix argument.
 */

char *maknam(dest, name, suffix)
char *dest, *name, *suffix;
   {
   register char *d, *pre, *suf;
   char *mark;

   d = dest;
   pre = name;
   suf = suffix;
   mark = pre;
   while (*pre) 		/* find last slash */
      if (*pre++ == '/')
         mark = pre;
   pre = mark;
   mark = 0;
   while (*d = *pre++)		/* copy from last slash into dest */
      if (*d++ == '.')		/*   look for last dot, too */
         mark = d - 1;
   if (mark)			/* if no dot, just append suffix */
      d = mark;
   while (*d++ = *suf++) ;	/* copy suffix into dest */
   return (dest);
   }
