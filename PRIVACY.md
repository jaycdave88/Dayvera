# Dayvera privacy policy

Last updated: September 4, 2026

Dayvera is a local-first wellness app. It has no Dayvera account,
app-managed server, advertising, analytics, or cross-app tracking.

## Data the app uses

- With your permission, Dayvera reads supported sleep, heart-rate,
  heart-rate variability, resting-heart-rate, respiratory-rate, blood-oxygen,
  temperature, activity, workout, and standard body-composition records from
  Apple Health. Body weight, body-fat percentage, lean body mass, and BMI are
  progress context only and never change readiness or workout recommendations.
  The app keeps non-identifying source and device information so it can explain
  which app or wearable supplied a signal. It does not import proprietary vendor
  scores that lack an Apple Health equivalent.
- Workout templates, active drafts, preferences, applied schedule state, and
  completed workout history are stored in the app's private container. Workout
  history includes session timing, readiness context, sets, loads, notes, and
  Apple Health export status.
- If you connect Calendar, the app reads relevant commitments from only the
  calendars you select. After confirmation, it can create a detailed workout
  event on one selected calendar and a neutral event titled “Busy” on other
  selected calendars. The Busy event contains no health or workout details.
  Your Calendar providers may sync those events according to your account
  settings.
- If you approve wake alarms, the app creates and manages only its own AlarmKit
  alarms.

## Sharing and network use

Dayvera does not send Apple Health samples, workout records, Calendar data,
or readiness results to the developer or to an app-managed cloud. Exercise
metadata and illustrations are downloaded from RepDB over HTTPS; health and
workout data are never attached to those requests. As with any network request,
the catalog host can receive standard connection metadata under its own policy.

When you finish a workout, you can grant write access for Dayvera to save a
strength workout to Apple Health. Apple Health, your Calendar provider, and your
device backups are governed by Apple's and the relevant provider's policies.
Dayvera marks its Application Support data as excluded from device backups.
Its private-state files and SwiftData/Core Data store use protection that makes
them available only after the first unlock following a reboot, so approved
background handling can read app state while the phone is later locked. Apple
Health samples themselves may remain unreadable until the phone is unlocked and
Dayvera refreshes. The active-workout draft file uses complete protection
while locked.

## Control and deletion

You can change Apple Health and Calendar permissions in iOS Settings. Use Undo
in Plan to remove app-owned schedule items. Deleting Dayvera removes its
local container; items already written to Apple Health or Calendar remain under
your control in those apps.

Dayvera provides wellness guidance, not medical diagnosis or treatment.
For a privacy question, contact the repository owner through
[the Dayvera project](https://github.com/jaycdave88/Dayvera) without
posting personal health information publicly.

## Nutrition and meal photos

Dayvera stores your nutrition profile, meal entries, optional meal thumbnails, daily source choices, completeness flags, measurements and target revisions locally. Saved photos are normalized to remove embedded metadata and stored with complete file protection, excluded from backup. Unsaved captures are discarded. Deleting a meal removes its associated image. No photo is sent to a cloud model.

Food identification uses Apple's on-device Foundation Models when available. The bundled USDA reference catalog supplies nutrient values, scaled by the portions you review. Photo-derived portions remain estimates. The optional dietary import reads calories, protein, carbohydrates and fat from Apple Health. One selected source counts per day, and meals are not exported to Health. Turning import off clears its in-memory samples.
