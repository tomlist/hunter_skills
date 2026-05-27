---
name: go
description: Read task.yaml and execute all pending tasks in order, updating status and summary after each task completes. Appends a new empty task when all tasks are done.
---

If the argument is `init`:

1. Check if `task.yaml` already exists in the current working directory.
   - If it exists, tell the user and stop (do not overwrite).
   - If it does not exist, create `task.yaml` with one empty placeholder task:
     ```yaml
     tasks:
       - id: 1
         content: ""
         status: pending
         summary: ""
         time:
           start: ""
           finish: ""
     ```
   - Tell the user the file has been created and they can edit `content` to add their first task.
   - Stop.

Otherwise, read the file `task.yaml` in the current working directory. The file contains a list of tasks with this structure:

```yaml
tasks:
  - id: <task_id>
    content: <what to do>
    status: <pending|in_progress|done|failed>
    summary: <completion summary, filled in after task completes>
    time:
      start: <ISO 8601 timestamp, set when task processing begins>
      finish: <ISO 8601 timestamp, set when task completes>
```

Execute the following workflow:

1. Parse `task.yaml` and identify all tasks where `status` is `pending`.
2. For each pending task (in order by id):
   a. Update its `status` to `in_progress` in `task.yaml`, and set `time.start` to the current system time.
   b. Execute the task described in `content`.
   c. After completion, update `status` to `done` (or `failed` if it could not be completed).
   d. Write a concise `summary` describing what was actually done (or why it failed).
   e. Set `time.finish` to the current ISO 8601 timestamp.
   f. Save `task.yaml` after each task so progress is persisted.
3. After all tasks are processed, report a final summary table showing each task id, status, and summary.
4. After completing all tasks (including if there were no pending tasks), append a new empty task to `task.yaml` with:
   - `id`: next integer after the current maximum id
   - `content`: ""
   - `status`: pending
   - `summary`: ""
   - `time`:
     - `start`: current ISO 8601 timestamp (e.g. 2026-05-22T14:30:00+08:00)
     - `finish`: ""
   This placeholder makes it easy for the user to edit and add the next task.

If `task.yaml` does not exist, tell the user and stop.
