FROM rocker/geospatial:4.5.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      libsecret-1-0 \
      libabsl-dev \
      cmake \
  && rm -rf /var/lib/apt/lists/*

RUN bash -lc "echo \"options(repos = c(CRAN='https://cloud.r-project.org'), \
    Ncpus = max(1L, parallel::detectCores()-1L))\" \
    >> /usr/local/lib/R/etc/Rprofile.site"

RUN R -q -e "install.packages(c('renv','here','httr2','glue','scales','DT','plotly','tidyterra','mapview','exactextractr','rmapshaper','knitr','kableExtra'))"

EXPOSE 8787
