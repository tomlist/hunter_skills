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
           created: ""
           start: ""
           finish: ""
     ```
   - Tell the user the file has been created and they can edit `content` to add their first task.
   - Stop.

If the argument is `clear`:

1. Read the existing `task.yaml` in the current working directory. If it does not exist, tell the user and stop.
2. Parse all tasks. Identify tasks where `content` is an empty string (`""`).
3. **Keep the last task** in the list (highest `id`), even if its `content` is empty — this is the active placeholder task.
4. **Remove all other tasks** with empty `content` (they are stale placeholders that were never filled).
5. **Renumber**: After removing stale tasks, reassign `id` values to the entire remaining list starting from 1, incrementing by 1, preserving the original order. Only change `id` values — do not modify `content`, `status`, `summary`, or `time`.
6. If no tasks were removed and no renumbering was needed, tell the user the task list is already clean and stop.
7. Save `task.yaml` and report:
   - How many empty tasks were removed.
   - The new id range (e.g. "IDs renumbered: now 1–10").
   - Stop.

If the argument is a non-empty string (not `init` and not `clear`), treat it as task input from the user:

1. Read the existing `task.yaml` in the current working directory. If it does not exist, tell the user to run `/go init` first and stop.

2. Find the most recent **non-empty** task (highest `id` where `content != ""`). If no such task exists, treat the input as a new task and skip to step 4.

3. Evaluate whether the user's input is a **follow-up** to that task or a **new task**. Use these heuristics:

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

4. **If follow-up**, update the previous non-empty task in place:
   a. **Merge strategy**:
      - If the follow-up adds a constraint or clarification (e.g. "用 JWT 不要 session"), append it to the original `content` after a semicolon: `"原内容; 补充约束"`.
      - If the follow-up corrects or replaces part of the original intent, rewrite `content` as a single coherent sentence that incorporates both the original goal and the correction.
      - If the previous task's `status` is `done` or `failed`, do **not** modify `content` — append the follow-up as a note to `summary` instead (prefix with "Follow-up: ").
   b. Any **empty placeholder tasks** that exist above this task in the list are left untouched; they will be cleaned up by `clear`.
   c. Save `task.yaml` and tell the user which task was updated (show id), and show both the old and new `content` (or `summary` if appended there).
   d. Proceed to **Execute pending tasks** below.

5. **If new task**:

   a. **Check for empty placeholder**: Look at the task with the highest `id` in the full list (including empty ones). If its `content` is `""`, **fill it in place** instead of creating a new task:
      - Set `content` to the summarized task description.
      - Set `time.created` to the current ISO 8601 timestamp.
      - Leave `time.start` and `time.finish` empty — they are set during execution.
      - Save `task.yaml` and tell the user the placeholder task was filled (show id and content).
      - Proceed to **Execute pending tasks** below.

   b. If the task with the highest `id` already has non-empty `content`, append a new task:
      - Summarize the user's input into a clear, actionable task description (`content`). Follow these principles:
         - Keep the summary concise and focused on the goal, not implementation details.
         - Use the same language (Chinese/English) as the user's input.
         - If the input is vague, make it more specific without inventing requirements.
      - Determine the next `id`: find the maximum existing `id` in `task.yaml` and add 1.
      - Append a new task to the `tasks` list with:
         - `id`: the next integer
         - `content`: the summarized task description (quoted string)
         - `status`: `pending`
         - `summary`: `""`
         - `time`:
           - `created`: current ISO 8601 timestamp (e.g. `2026-06-15T14:30:00+08:00`)
           - `start`: `""`
           - `finish`: `""`
      - Save `task.yaml` and tell the user the task has been added (show the id and content).
      - Proceed to **Execute pending tasks** below.

---

Otherwise (no argument), read the file `task.yaml` in the current working directory. The file contains a list of tasks with this structure:

```yaml
tasks:
  - id: <task_id>
    content: <what to do>
    status: <pending|in_progress|done|failed>
    summary: <completion summary, filled in after task completes>
    time:
      created: <ISO 8601 timestamp, set when the task is first added>
      start: <ISO 8601 timestamp, set when task execution begins>
      finish: <ISO 8601 timestamp, set when task completes>
```

Execute the following workflow:

1. Parse `task.yaml` and identify all tasks where `status` is `pending` **and** `content` is not empty. Skip empty placeholder tasks — they are not executable.
2. For each qualifying pending task (in order by id):
   a. Update its `status` to `in_progress` and set `time.start` to the current ISO 8601 timestamp. Save `task.yaml`.
   b. Execute the task described in `content`.
   c. After completion, update `status` to `done` (or `failed` if it could not be completed).
   d. Write a concise `summary` describing what was actually done (or why it failed).
   e. Set `time.finish` to the current ISO 8601 timestamp.
   f. Save `task.yaml` after each task so progress is persisted.
3. After all tasks are processed, report a final summary table showing each task's id, status, and summary.
4. After completing all tasks (including if there were no pending tasks to execute), append a new empty placeholder task to `task.yaml`:
   - `id`: next integer after the current maximum id
   - `content`: `""`
   - `status`: `pending`
   - `summary`: `""`
   - `time`:
     - `created`: current ISO 8601 timestamp
     - `start`: `""`
     - `finish`: `""`

   **Exception**: If the task with the current highest `id` already has empty `content`, do **not** append another placeholder — one is already present.

If `task.yaml` does not exist, tell the user and stop.
