# Sleep Coach privacy policy

Last updated: September 4, 2026

Sleep Coach is a local-first wellness app. It has no Sleep Coach account,
app-managed server, advertising, analytics, or cross-app tracking.

## Data the app uses

- With your permission, Sleep Coach reads sleep, heart-rate variability, and
  resting heart rate from Apple Health. The contributing source name is kept so
  the app can explain which device or app supplied a signal.
- Workout templates, active drafts, preferences, applied schedule state, and
  completed workout history are stored in the app's private container. Workout
  history includes session timing, readiness context, sets, loads, notes, and
  Apple Health export status.
- If you connect Calendar, the app reads the first relevant commitment for the
  next day. It creates a gym event only after confirmation and uses the generic
  note “Created by Sleep Coach.” Your Calendar provider may sync that event
  according to your own account settings.
- If you approve wake alarms, the app creates and manages only its own AlarmKit
  alarms.

## Sharing and network use

Sleep Coach does not send Apple Health samples, workout records, Calendar data,
or readiness results to the developer or to an app-managed cloud. Exercise
metadata and illustrations are downloaded from RepDB over HTTPS; health and
workout data are never attached to those requests. As with any network request,
the catalog host can receive standard connection metadata under its own policy.

When you finish a workout, you can grant write access for Sleep Coach to save a
strength workout to Apple Health. Apple Health, your Calendar provider, and your
device backups are governed by Apple's and the relevant provider's policies.
Sleep Coach marks its Application Support data as excluded from device backups.
Its private-state files and SwiftData/Core Data store use protection that makes
them available only after the first unlock following a reboot, so approved
background handling can read app state while the phone is later locked. Apple
Health samples themselves may remain unreadable until the phone is unlocked and
Sleep Coach refreshes. The active-workout draft file uses complete protection
while locked.

## Control and deletion

You can change Apple Health and Calendar permissions in iOS Settings. Use Undo
in Plan to remove app-owned schedule items. Deleting Sleep Coach removes its
local container; items already written to Apple Health or Calendar remain under
your control in those apps.

Sleep Coach provides wellness guidance, not medical diagnosis or treatment.
For a privacy question, contact the repository owner through
[the SleepCoach project](https://github.com/jaycdave88/SleepCoach) without
posting personal health information publicly.
