RELEASE_URL := https://github.com/LiteNoteProject/litenote-builds/releases/download/v0.17.1/

all-zip: litenote-full-win64.zip litenote-full-linux64.tar.gz
all-exe: litenote-tk-win64.exe litenote-tk-linux64

vanillawish/win64:
	mkdir vanillawish || true
	wget -O $@ http://www.ch-werner.de/AndroWish/vanillawish-e5dc71ed9d-win64.exe

vanillawish/linux64:
	mkdir vanillawish || true
	wget -O $@ http://www.ch-werner.de/AndroWish/vanillawish-e5dc71ed9d-linux64

litenote-tk-win64.exe: vanillawish/win64 $(wildcard app/*)
	cat vanillawish/win64 > $@.zip
	zip -A $@.zip
	zip -9r $@.zip app
	mv $@.zip $@
	chmod +x $@

litenote-tk-linux64: vanillawish/linux64 $(wildcard app/*)
	cat vanillawish/linux64 > $@.zip
	zip -A $@.zip
	zip -9r $@.zip app
	mv $@.zip $@
	chmod +x $@

litenote-full-win64.zip: litenote-tk-win64.exe
	mkdir litenote-full-win64
	cd litenote-full-win64; wget -O tmp.zip $(RELEASE_URL)/litenote-core-win64.zip && unzip tmp.zip && rm -f tmp.zip
	cd litenote-full-win64; cp ../litenote-tk-win64.exe litenote-gui.exe
	cd litenote-full-win64; zip -9 -r ../$@ .
	rm -rf litenote-full-win64

litenote-full-linux64.tar.gz: litenote-tk-linux64
	mkdir litenote-full-linux64
	cd litenote-full-linux64; wget -O - $(RELEASE_URL)/litenote-core-linux64.tar.gz | tar xzf -
	cd litenote-full-linux64; cp ../litenote-tk-linux64 litenote-gui
	tar cvzf $@ litenote-full-linux64
	rm -rf litenote-full-linux64
