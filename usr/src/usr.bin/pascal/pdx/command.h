/*
 * Copyright (c) 1980 Regents of the University of California.
 * All rights reserved.  The Berkeley software License Agreement
 * specifies the terms and conditions for redistribution.
 *
 *	@(#)command.h	5.2 (Berkeley) %G%
 */

/*
 * Definitions for the command module.
 *
 * The command module scans and parses the commands.  This includes
 * input file management (i.e. the "source" command), and some error
 * handling.
 */

char *initfile;		/* file to read initial commands from */
BOOLEAN nlflag;		/* for error and signal recovery */
prompt();		/* print a prompt */
int yyparse();		/* parser generated by yacc */
lexinit();		/* initialize debugger symbol table */
gobble();		/* eat input up to a newline for error recovery */
remake();		/* recompile program, read in new namelist */
alias();		/* create an alias */
BOOLEAN isstdin();	/* input is from standard input */
