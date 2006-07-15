/*
 * runscript.c
 * Handle launching of Gentoo init scripts.
 *
 * Copyright 1999-2004 Gentoo Foundation
 * Distributed under the terms of the GNU General Public License v2
 * $Header$
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dlfcn.h>

#include "rcscripts/rcutil.h"
#include "rcscripts/rcdefines.h"
#include "librccore/internal/rccore.h"

#define IS_SBIN_RC()	((caller) && (0 == strcmp (caller, SBIN_RC)))

#if defined(WANT_SELINUX)
static void (*selinux_run_init_old) (void);
static void (*selinux_run_init_new) (int argc, char **argv);

void setup_selinux (int argc, char **argv);
#endif

char ** filter_environ (char *caller);

extern char **environ;

#if defined(WANT_SELINUX)
void
setup_selinux (int argc, char **argv)
{
  void *lib_handle = NULL;

  lib_handle = dlopen (SELINUX_LIB, RTLD_NOW | RTLD_GLOBAL);
  if (NULL != lib_handle)
    {
      selinux_run_init_old = dlsym (lib_handle, "selinux_runscript");
      selinux_run_init_new = dlsym (lib_handle, "selinux_runscript2");

      /* Use new run_init if it exists, else fall back to old */
      if (NULL != selinux_run_init_new)
	selinux_run_init_new (argc, argv);
      else if (NULL != selinux_run_init_old)
	selinux_run_init_old ();
      else
	{
	  /* This shouldnt happen... probably corrupt lib */
	  fprintf (stderr, "Run_init is missing from runscript_selinux.so!\n");
	  exit (127);
	}
    }
}
#endif

char **
filter_environ (char *caller)
{
  char **myenv = NULL;
  char **whitelist = NULL;
  char *env_name = NULL;
  int check_profile = 1;
  int count = 0;

  if (NULL != getenv (SOFTLEVEL) && !IS_SBIN_RC ())
    /* Called from /sbin/rc, but not /sbin/rc itself, so current
     * environment should be fine */
    return environ;

  if (rc_is_file (SYS_WHITELIST, TRUE))
    whitelist = rc_get_list_file (whitelist, SYS_WHITELIST);
  else
    EWARN ("System environment whitelist missing!\n");

  if (rc_is_file (USR_WHITELIST, TRUE))
    whitelist = rc_get_list_file (whitelist, USR_WHITELIST);

  if (NULL == whitelist)
    /* If no whitelist is present, revert to old behaviour */
    return environ;

  if (!rc_is_file (PROFILE_ENV, TRUE))
    /* XXX: Maybe warn here? */
    check_profile = 0;

  str_list_for_each_item (whitelist, env_name, count)
    {
      char *env_var = NULL;
      char *tmp_p = NULL;
      int env_len = 0;

      env_var = getenv (env_name);
      if (NULL != env_var)
	goto add_entry;

      if (1 == check_profile)
	{
	  char *tmp_env_name = NULL;
	  int tmp_len = 0;

	  /* The entries in PROFILE_ENV is of the form:
	   * export VAR_NAME=value */
	  tmp_len = strlen (env_name) + strlen ("export ") + 1;
	  tmp_env_name = xmalloc (tmp_len * sizeof (char));
	  if (NULL == tmp_env_name)
	    goto error;

	  snprintf (tmp_env_name, tmp_len, "export %s", env_name);

	  env_var = rc_get_cnf_entry (PROFILE_ENV, tmp_env_name, NULL);
	  free (tmp_env_name);
	  if ((NULL == env_var) && (rc_errno_is_set ()))
	    goto error;
	  else if (NULL != env_var)
	    goto add_entry;
	}

      continue;

add_entry:
      env_len = strlen (env_name) + strlen (env_var) + 2;
      tmp_p = xmalloc (env_len * sizeof (char));
      if (NULL == tmp_p)
	goto error;

      snprintf (tmp_p, env_len, "%s=%s", env_name, env_var);
      str_list_add_item (myenv, tmp_p, error);
    }

  str_list_free (whitelist);

  if (NULL == myenv)
    {
      char *tmp_str;

      tmp_str = xstrndup (DEFAULT_PATH, strlen (DEFAULT_PATH));
      if (NULL == tmp_str)
	goto error;

      /* If all else fails, just add a default PATH */
      str_list_add_item (myenv, strdup (DEFAULT_PATH), error);
    }

  return myenv;

error:
  str_list_free (myenv);
  str_list_free (whitelist);

  return NULL;
}

int
main (int argc, char *argv[])
{
  char *myargs[32];
  char **myenv = NULL;
  char *caller = argv[1];
  int new = 1;

  /* Need to be /bin/bash, else BASH is invalid */
  myargs[0] = "/bin/bash";
  while (argv[new] != 0)
    {
      myargs[new] = argv[new];
      new++;
    }
  myargs[new] = NULL;

  /* Do not do help for /sbin/rc */
  if (argc < 3 && !IS_SBIN_RC ())
    {
      execv (RCSCRIPT_HELP, myargs);
      exit (1);
    }

  /* Setup a filtered environment according to the whitelist */
  myenv = filter_environ (caller);
  if (NULL == myenv)
    {
      EWARN ("%s: Failed to filter the environment!\n", caller);
      /* XXX: Might think to bail here, but it could mean the system
       *      is rendered unbootable, so rather not */
      myenv = environ;
    }

#if defined(WANT_SELINUX)
  /* Ok, we are ready to go, so setup selinux if applicable */
  setup_selinux (argc, argv);
#endif

  if (!IS_SBIN_RC ())
    {
      if (execve ("/sbin/runscript.sh", myargs, myenv) < 0)
	exit (1);
    }
  else
    {
      if (execve ("/bin/bash", myargs, myenv) < 0)
	exit (1);
    }

  return 0;
}
