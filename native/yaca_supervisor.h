/*
Author: WaterRun
Date: 2026-09-23
File: yaca_supervisor.h
Description: Linux subreaper lifecycle, descendant cleanup, and activity result.
*/

/* Linux activity supervision. Each activity owns a subreaper, not just a
** process group: double forks and setsid() still belong to the activity.
** The control pipe also requests cleanup when yaca exits unexpectedly.
** This is lifecycle management, not a sandbox against hostile processes. */
#ifndef YACA_SUPERVISOR_H
#define YACA_SUPERVISOR_H

#include <sys/prctl.h>

#define YACA_SUPERVISOR_MAGIC 0x59414341U
/* @struct yaca_supervisor_result Status sent by the activity subreaper to its parent.
 * @field magic uint32_t Protocol marker identifying a complete result message.
 * @field leader_status int Wait status of the original activity process.
 * @field cancelled int Whether cleanup was triggered by cancellation.
 */
typedef struct yaca_supervisor_result
{
  uint32_t magic;
  int leader_status;
  int cancelled;
} yaca_supervisor_result;

static volatile sig_atomic_t yaca_supervisor_interrupted;

/* Records an interrupt for the activity subreaper.
 * @param signal_number int The signal number bound to yaca supervisor interrupt.
 * @return void result No value; sets the process-local interrupted flag.
 */
static void yaca_supervisor_interrupt(int signal_number)
{
  (void)signal_number;
  yaca_supervisor_interrupted = 1;
}

/* Only direct, unreaped children are signalled. Their PIDs cannot be reused
** before this supervisor reaps them. Orphans become direct children on the
** next pass, including descendants which created a new session. */
/* Signals each currently unreaped direct child of the subreaper.
 * @param children_fd int The children fd bound to yaca supervisor kill children.
 * @return int result 1 when all listed children were signalled or gone, 0 on malformed input or error.
 */
static int yaca_supervisor_kill_children(int children_fd)
{
  char buffer[4096];
  unsigned long child = 0;
  ssize_t count;
  size_t index;
  if (lseek(children_fd, 0, SEEK_SET) < 0) return 0;
  for (;;)
  {
    do { count = read(children_fd, buffer, sizeof(buffer)); }
    while (count < 0 && errno == EINTR);
    if (count < 0) return 0;
    for (index = 0; index < (size_t)count; index++)
    {
      unsigned char byte = (unsigned char)buffer[index];
      if (byte >= '0' && byte <= '9')
      {
        if (child > ((unsigned long)INT_MAX - (byte - '0')) / 10U) return 0;
        child = child * 10U + (byte - '0');
      }
      else if (byte == ' ' || byte == '\n')
      {
        if (child > 0 && kill((pid_t)child, SIGKILL) != 0 && errno != ESRCH)
          return 0;
        child = 0;
      }
      else return 0;
    }
    if (count == 0) break;
  }
  return child == 0 || kill((pid_t)child, SIGKILL) == 0 || errno == ESRCH;
}

/* Closes inherited file descriptors except the explicit keep set.
 * @param keep const_int* The keep bound to yaca supervisor close inherited.
 * @param keep_count size_t The keep count bound to yaca supervisor close inherited.
 * @return int result 1 after scanning /proc/self/fd, 0 when it cannot be opened.
 */
static int yaca_supervisor_close_inherited(const int *keep, size_t keep_count)
{
  DIR *directory = opendir("/proc/self/fd");
  struct dirent *entry;
  if (directory == NULL) return 0;
  while ((entry = readdir(directory)) != NULL)
  {
    char *end;
    long value = strtol(entry->d_name, &end, 10);
    size_t index;
    int retained = value == dirfd(directory);
    if (*entry->d_name == '\0' || *end != '\0' || value < 0 || value > INT_MAX)
      continue;
    for (index = 0; index < keep_count; index++)
      if (value == keep[index]) retained = 1;
    if (!retained) close((int)value);
  }
  closedir(directory);
  return 1;
}

/* Writes one complete status message to the parent pipe.
 * @param descriptor int POSIX file descriptor under inspection.
 * @param bytes const_void* Raw byte buffer supplied to the native operation.
 * @param size size_t The size bound to yaca supervisor send.
 * @return int result 1 if every byte was written, otherwise 0.
 */
static int yaca_supervisor_send(int descriptor, const void *bytes, size_t size)
{
  ssize_t written;
  do { written = write(descriptor, bytes, size); }
  while (written < 0 && errno == EINTR);
  return written == (ssize_t)size;
}

/* Called only in a fresh, single-threaded fork child; never returns to Lua. */
/* Runs an activity under a subreaper and cleans all descendants before exit.
 * @param input int Owned process or terminal input state.
 * @param input_writer int The input writer bound to yaca supervisor run.
 * @param output int Caller-provided output buffer or result destination.
 * @param error_output int The error output bound to yaca supervisor run.
 * @param control int The control bound to yaca supervisor run.
 * @param status_output int The status output bound to yaca supervisor run.
 * @param cwd const_char* Working directory selected for the child process.
 * @param executable const_char* Selected executable path or process image.
 * @param arguments char** Child-process argument vector or owned argument storage.
 * @param environment char** Child-process environment being constructed or released.
 * @param stdin_bytes const_char* The stdin bytes bound to yaca supervisor run.
 * @param stdin_length size_t The stdin length bound to yaca supervisor run.
 * @return void result Does not return to Lua; reports the leader status through status_output and exits.
 */
static void yaca_supervisor_run(
  int input, int input_writer, int output, int error_output,
  int control, int status_output, const char *cwd, const char *executable,
  char **arguments, char **environment, const char *stdin_bytes, size_t stdin_length)
{
  int children_fd, leader_done = 0, cancelled = 0, startup_error = 0;
  int keep[] = { input, input_writer, output, error_output, control, status_output };
  char children_path[96];
  pid_t leader;
  size_t input_offset = 0;
  struct sigaction action;
  sigset_t mask;
  yaca_supervisor_result result;
  const struct timespec pause_time = { 0, 10000000L };

  memset(&result, 0, sizeof(result));
  memset(&action, 0, sizeof(action));
  sigemptyset(&action.sa_mask);
  sigemptyset(&mask);
  sigprocmask(SIG_SETMASK, &mask, NULL);
  action.sa_handler = SIG_DFL;
  sigaction(SIGCHLD, &action, NULL);
  action.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &action, NULL);
  action.sa_handler = yaca_supervisor_interrupt;
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
  yaca_supervisor_interrupted = 0;

  if (!yaca_supervisor_close_inherited(keep, sizeof(keep) / sizeof(keep[0]))
      || prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0)
  {
    startup_error = errno == 0 ? ENOSYS : errno;
    yaca_supervisor_send(status_output, &startup_error, sizeof(startup_error));
    _exit(126);
  }
  snprintf(children_path, sizeof(children_path), "/proc/self/task/%ld/children", (long)getpid());
  children_fd = open(children_path, O_RDONLY | O_CLOEXEC);
  if (children_fd < 0)
  {
    startup_error = errno;
    yaca_supervisor_send(status_output, &startup_error, sizeof(startup_error));
    _exit(126);
  }
  leader = fork();
  if (leader < 0)
  {
    startup_error = errno;
    yaca_supervisor_send(status_output, &startup_error, sizeof(startup_error));
    _exit(126);
  }
  if (leader == 0)
  {
    int streams[] = { input, output, error_output };
    size_t index;
    action.sa_handler = SIG_DFL;
    sigaction(SIGPIPE, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    close(control);
    close(status_output);
    close(children_fd);
    if (input_writer >= 0) close(input_writer);
    if (setpgid(0, 0) != 0 || (cwd != NULL && chdir(cwd) != 0)) _exit(126);
    /* The caller ensures these source descriptors are above the standard
    ** streams, so dup2 cannot overwrite another stream's source. */
    for (index = 0; index < 3; index++)
      if (dup2(streams[index], (int)index) < 0) _exit(126);
    for (index = 0; index < 3; index++) close(streams[index]);
    execve(executable, arguments, environment);
    _exit(127);
  }
  close(input);
  close(output);
  close(error_output);
  if (!yaca_supervisor_send(status_output, &startup_error, sizeof(startup_error)))
    cancelled = 1;
  for (;;)
  {
    char command;
    ssize_t received;
    int child_status;
    pid_t child;
    do { received = read(control, &command, 1); }
    while (received < 0 && errno == EINTR);
    if (received >= 0 || (errno != EAGAIN && errno != EWOULDBLOCK)
        || yaca_supervisor_interrupted) cancelled = 1;
    for (;;)
    {
      child = waitpid(-1, &child_status, WNOHANG);
      if (child == leader)
      {
        result.leader_status = child_status;
        leader_done = 1;
      }
      if (child < 0 && errno == EINTR) continue;
      if (child <= 0) break;
    }
    if (child < 0 && errno == ECHILD && leader_done)
    {
      result.magic = YACA_SUPERVISOR_MAGIC;
      result.cancelled = cancelled;
      yaca_supervisor_send(status_output, &result, sizeof(result));
      _exit(0);
    }
    if (cancelled)
    {
      if (input_writer >= 0) { close(input_writer); input_writer = -1; }
      /* On a permission failure continue supervising; never emit proof of
      ** completion while an unreaped descendant still exists. */
      (void)yaca_supervisor_kill_children(children_fd);
    }
    else if (input_writer >= 0)
    {
      ssize_t written = 0;
      if (input_offset < stdin_length)
        written = write(input_writer, stdin_bytes + input_offset, stdin_length - input_offset);
      if (written > 0) input_offset += (size_t)written;
      if (input_offset == stdin_length || (written < 0 && errno != EINTR
          && errno != EAGAIN && errno != EWOULDBLOCK))
      { close(input_writer); input_writer = -1; }
    }
    nanosleep(&pause_time, NULL);
  }
}

#endif
