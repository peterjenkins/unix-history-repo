# hints/aix.sh
# AIX 3.x.x hints thanks to Wayne Scott <wscott@ichips.intel.com>
# AIX 4.1 hints thanks to Christopher Chan-Nui <channui@austin.ibm.com>.
# AIX 4.1 pthreading by Christopher Chan-Nui <channui@austin.ibm.com> and
#         Jarkko Hietaniemi <jhi@iki.fi>.
# Merged on Mon Feb  6 10:22:35 EST 1995 by
#   Andy Dougherty  <doughera@lafcol.lafayette.edu>


# Configure finds setrgid and setruid, but they're useless.  The man
# pages state:
#    setrgid: The EPERM error code is always returned.
#    setruid: The EPERM error code is always returned. Processes cannot
#             reset only their real user IDs.
d_setrgid='undef'
d_setruid='undef'

alignbytes=8

usemymalloc='n'

so="a"
dlext="so"

# Make setsockopt work correctly.  See man page.
# ccflags='-D_BSD=44'

# uname -m output is too specific and not appropriate here
case "$archname" in
'') archname="$osname" ;;
esac

case "$osvers" in
3*) d_fchmod=undef
    ccflags="$ccflags -D_ALL_SOURCE"
    ;;
*)  # These hints at least work for 4.x, possibly other systems too.
    ccflags="$ccflags -D_ALL_SOURCE -D_ANSI_C_SOURCE -D_POSIX_SOURCE"
    case "$cc" in
     *gcc*) ;;
     *) ccflags="$ccflags -qmaxmem=8192" ;;
    esac
    nm_opt='-B'
    ;;
esac

# These functions don't work like Perl expects them to.
d_setregid='undef'
d_setreuid='undef'

# Changes for dynamic linking by Wayne Scott <wscott@ichips.intel.com>
#
# Tell perl which symbols to export for dynamic linking.
case "$cc" in
*gcc*) ccdlflags='-Xlinker -bE:perl.exp' ;;
*) ccdlflags='-bE:perl.exp' ;;
esac

# The first 3 options would not be needed if dynamic libs. could be linked
# with the compiler instead of ld.
# -bI:$(PERL_INC)/perl.exp  Read the exported symbols from the perl binary
# -bE:$(BASEEXT).exp        Export these symbols.  This file contains only one
#                           symbol: boot_$(EXP)  can it be auto-generated?
case "$osvers" in
3*) 
lddlflags='-H512 -T512 -bhalt:4 -bM:SRE -bI:$(PERL_INC)/perl.exp -bE:$(BASEEXT).exp -e _nostart -lc'
    ;;
*) 
lddlflags='-bhalt:4 -bM:SRE -bI:$(PERL_INC)/perl.exp -bE:$(BASEEXT).exp -b noentry -lc'

;;
esac

if [ "X$usethreads" = "X$define" ]; then
    ccflags="$ccflags -DNEED_PTHREAD_INIT"
    case "$cc" in
    xlc_r | cc_r)
	;;
    cc | '') 
	cc=xlc_r # Let us be stricter.
        ;;
    *)
	cat >&4 <<EOM
Unknown C compiler '$cc'.
For pthreads you should use the AIX C compilers xlc_r or cc_r.
Cannot continue, aborting.
EOM
	exit 1
	;;
    esac

    # Add the POSIX threads library and the re-entrant libc.

    lddlflags=`echo $lddlflags | sed 's/ -lc$/ -lpthreads -lc_r -lc/'`

    # Add the c_r library to the list of libraries wanted
    # Make sure the c_r library is before the c library or
    # make will fail.
    set `echo X "$libswanted "| sed -e 's/ c / c_r c /'`
    shift
    libswanted="$*"
fi
