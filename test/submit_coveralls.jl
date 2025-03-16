ENV["CI"] = "true"
ENV["COVERALLS_CI"] = "jenkins"
COVERALLS_REPO_TOKEN="qlUGERZPR64t3RGZgpUAaNIM6dr6VyNFg"
using Pkg
using Coverage

coverage = process_folder()
LCOV.writefile("coverage-lcov.info", coverage)