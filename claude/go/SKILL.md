---
name: go
description: Manage task.yaml — add new tasks from terminal input, execute pending tasks in order, and append empty placeholder tasks.
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

If the argument is a non-empty string (not `init`), treat it as task input from the user:

1. Read the existing `task.yaml` in the current working directory. If it does not exist, tell the user to run `/go init` first and stop.

2. Find the most recent task (highest `id`) in `task.yaml`. Evaluate whether the user's input is a **follow-up** to that task or a **new task**. Use these heuristics:

   **Follow-up indicators** (input refines, clarifies, or extends the previous task):
   - The input references the same topic, feature, or area as the previous task's `content`.
   - The input uses continuations like "also", "additionally", "and for that", "don't forget", "另一个", "还有", "另外", "补充".
   - The input is a clarification or refinement that doesn't stand alone ("actually, use X instead", "make it also do Y", "用X代替Y", "也加上Z").
   - The input is brief and reads like an amendment rather than a self-contained request.
   - The previous task's `status` is `pending` or `in_progress` (active tasks are more likely to receive follow-ups).

   **New task indicators** (input introduces a separate piece of work):
   - The input introduces a completely different topic, feature, or area.
   - The input is a self-contained, complete request that stands on its own.
   - The previous task's `status` is `done` or `failed` (closed tasks rarely receive follow-ups).

   When in doubt, prefer treating it as a **follow-up** if the previous task is still `pending`/`in_progress` and the topics overlap at all.

3. **If follow-up**, update the previous task in place:
   a. Merge the new information into the previous task's `content`: refine the description to incorporate the clarification, extension, or amendment. Preserve the original intent while integrating the new details.
   b. If the task has already been executed (`status` is `done` or `failed`), append the follow-up as a note to the task's `summary` instead of changing `content`.
   c. Save `task.yaml` and tell the user which task was updated (show id) and how the content changed.
   d. Stop.

4. **If new task**, append it to `task.yaml`:
   a. Parse the user's input and summarize it into a clear, actionable task description (`content`). Follow these principles:
      - Keep the summary concise and focused on the goal, not implementation details.
      - Use the same language (Chinese/English) as the user's input.
      - If the input is vague, make it more specific without inventing requirements.
   b. Determine the next `id`: find the maximum existing `id` in `task.yaml` and add 1.
   c. Append a new task to the `tasks` list with:
      - `id`: the next integer
      - `content`: the summarized task description (quoted string)
      - `status`: `pending`
      - `summary`: `""`
      - `time`:
        - `start`: current ISO 8601 timestamp (e.g. `2026-06-15T14:30:00+08:00`)
        - `finish`: `""`
   d. Save `task.yaml` and tell the user the task has been added (show the id and content).
   e. Stop.

Otherwise (no argument), read the file `task.yaml` in the current working directory. The file contains a list of tasks with this structure:

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
