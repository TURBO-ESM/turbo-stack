timestamp = $(shell date +%Y%m%d_%H%M%S)
untracked_files = $(shell git ls-files --others --directory --exclude=archive)

clean:
	rm -rf $(untracked_files)

archive:
	echo "Archiving the output files of this run..."
	mkdir -p archive/${timestamp}
	cp -r $(untracked_files) MOM_parameter_doc* archive/${timestamp}/
	echo "Run output files are stored in archive/${timestamp}/"

.PHONY: clean archive