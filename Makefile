APP := dist/Am I Shouting.app

.PHONY: app dmg run stop universal test clean

app:
	./Scripts/build-app.sh

universal:
	UNIVERSAL=1 ./Scripts/build-app.sh

# What a release ships: universal, then packaged as a disk image.
dmg: universal
	./Scripts/package-dmg.sh

run: app stop
	open "$(APP)"

stop:
	-@pkill -x AmIShouting 2>/dev/null || true

test:
	swift test

clean:
	rm -rf .build dist
