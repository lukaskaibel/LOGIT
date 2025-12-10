# Quick Start Guide - Default Exercises

## 🚀 Adding Files to Xcode (2 minutes)

### Step 1: Add DefaultExerciseService.swift
```
1. Open LOGIT.xcodeproj in Xcode
2. In Project Navigator, find "Services" folder
3. Right-click → "Add Files to LOGIT..."
4. Select: LOGIT/Services/DefaultExerciseService.swift
5. ✓ Uncheck "Copy items if needed"
6. ✓ Check "LOGIT" target
7. Click "Add"
```

### Step 2: Add default_exercises.json
```
1. In Project Navigator, right-click "LOGIT" folder
2. "New Group" → name it "Resources" (or use existing)
3. Right-click "Resources" → "Add Files to LOGIT..."
4. Select: LOGIT/Resources/default_exercises.json
5. ✓ Uncheck "Copy items if needed"
6. ✓ Check "LOGIT" target
7. Click "Add"
```

### Step 3: Build & Run
```
1. Clean: ⌘ + Shift + K
2. Build: ⌘ + B
3. Run: ⌘ + R
```

## ✅ Verification

After running the app, check:
- Console shows: "DefaultExerciseService: Loaded default exercises version 1"
- Exercises tab shows 200 exercises
- Exercise names are in your device language

## 📝 What You Get

- **200 exercises** ready to use
- **Localized** in English and German
- **Organized** by muscle group
- **Updates** automatically on new versions

## 🎯 Sample Exercises

**Chest:** Push-ups, Barbell Bench Press, Dumbbell Fly, Cable Crossovers...
**Back:** Pull-ups, Barbell Rows, Deadlift, Lat Pulldowns...
**Legs:** Squats, Leg Press, Lunges, Calf Raises...
**Shoulders:** Military Press, Lateral Raises, Arnold Press...
**Arms:** Barbell Curls, Tricep Dips, Hammer Curls...
**Core:** Crunches, Plank, Russian Twists, Leg Raises...
**Cardio:** Running, Cycling, Jump Rope, HIIT...

## 🔧 Technical Notes

- Exercises stored with names like `_default.exercise.pushups`
- `displayName` property handles localization automatically
- User custom exercises work exactly as before
- No Core Data migrations needed

## 📚 Full Documentation

See `DEFAULT_EXERCISES_IMPLEMENTATION.md` for:
- Complete technical details
- How the versioning system works
- Future update procedures
- Troubleshooting guide
