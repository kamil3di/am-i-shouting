APP := dist/ShoutMeter.app

.PHONY: app run stop universal clean

app:
	./Scripts/build-app.sh

universal:
	UNIVERSAL=1 ./Scripts/build-app.sh

run: app stop
	open $(APP)

stop:
	-@pkill -x ShoutMeter 2>/dev/null || true

clean:
	rm -rf .build dist
