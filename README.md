बहुत राम्रो। अब दुई काम गर्नुहोस्: पहिले GitHub मा सानो फाइल बनाउने, अनि ZIP upload गर्ने।
स्टेप १: ZIP फोनमा सेभ गर्नुहोस्
Claude को च्याटमा ZIP फाइलमा थिच्नुहोस् र Download गर्नुहोस्।
स्टेप २: GitHub मा workflow फाइल बनाउनुहोस्
ब्राउजरमा GitHub खोलेर nepali-sahayak रिपोमा जानुहोस् (मोबाइलमा "Desktop site" अन गर्दा सजिलो हुन्छ)।
Add file → Create new file थिच्नुहोस्।
फाइलको नाममा यो लेख्नुहोस्: .github/workflows/unzip-build.yml
तल को कोड पेस्ट गर्नुहोस्, अनि Commit changes थिच्नुहोस्।
name: Unzip and Build
on:
  push:
    paths: ['*.zip']
permissions:
  contents: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Unzip project
        run: |
          ZIP=$(ls *.zip | head -n 1)
          mkdir tmp
          unzip -q "$ZIP" -d tmp -x ".github/*" "*/.github/*"
          if [ "$(ls tmp | wc -l)" -eq 1 ] && [ -d "tmp/$(ls tmp)" ]; then
            cp -r "tmp/$(ls tmp)/." .
          else
            cp -r tmp/. .
          fi
          rm -rf tmp "$ZIP"
          git config user.name github-actions
          git config user.email actions@github.com
          git add -A
          git commit -m "Unzip project" || true
          git push
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 8.7
      - name: Build APK
        run: gradle assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: nepali-sahayak-apk
          path: app/build/outputs/apk/debug/*.apk
स्टेप ३: ZIP upload गर्नुहोस्
Add file → Upload files मा गएर ZIP छान्नुहोस् र Commit गर्नुहोस्।
स्टेप ४: APK लिनुहोस्
रिपोको Actions ट्याबमा जानुहोस्। हरियो ✓ आएपछि त्यो रन खोल्नुहोस्। तल Artifacts मा nepali-sahayak-apk डाउनलोड गरेर इन्स्टल गर्नुहोस्।
रातो ✗ आयो भने त्रुटि देखिने भाग (कालो लगमा रातो लेख) को स्क्रिनसट पठाउनुहोस्। पहिलो पटक error आउनु सामान्य हो, हामी ठीक गर्छौं।
