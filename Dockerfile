########################################################################################################################
# MoveApps R-SHINY SDK
########################################################################################################################

FROM rocker/geospatial:4.5.1

LABEL org.opencontainers.image.authors="us@couchbits.com"
LABEL org.opencontainers.image.vendor="couchbits GmbH"

# Security Aspects
# Create a non-root user
ARG username=moveapps
ARG uid=1001
# group `staff` b/c of:
# When running rocker with a non-root user the docker user is still able to install packages.
# The user docker is member of the group staff and could write to /usr/local/lib/R/site-library.
# https://github.com/rocker-org/rocker/wiki/managing-users-in-docker
ARG gid=staff
ENV USER=$username
ENV UID=$uid
ENV GID=$gid
ENV HOME=/home/$USER

RUN adduser --disabled-password \
    --gecos "Non-root user" \
    --uid $UID \
    --ingroup $GID \
    --home $HOME \
    $USER
# create working dir with correct ownership
RUN install -d -o moveapps -g staff $HOME/co-pilot-r
# create cache-directory for renv with correct ownership
RUN install -d -o moveapps -g staff $HOME/.cache/R

# Install Google Chrome for webshot2/chromote (PNG export of leaflet maps).
# Note: Ubuntu's `chromium` package is a snap stub that does not work in
# containers; we install Chrome from Google's APT repo instead.
# chromote auto-detects /usr/bin/google-chrome. Its default_chrome_args() only
# adds --no-sandbox/--disable-dev-shm-usage when it recognises the container
# (/.dockerenv or "docker" in /proc/self/cgroup), which the MoveApps runtime
# does not provide -- ShinyModule.R therefore sets those flags explicitly.
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget gnupg ca-certificates \
    && wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-linux.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

USER $USER
WORKDIR $HOME/co-pilot-r

# Set renv environment variables
ENV RENV_PATHS_CACHE=$HOME/.cache/R/renv
ENV RENV_CONFIG_REPOS_OVERRIDE=https://cloud.r-project.org
ENV RENV_CONFIG_SANDBOX_ENABLED=FALSE

# Install renv if not available
RUN R -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv')"

# Copy renv files first (for better Docker layer caching)
COPY --chown=$UID:$GID renv.lock .Rprofile ./
COPY --chown=$UID:$GID renv/activate.R renv/settings.dcf ./renv/
# Restore packages
RUN R -e 'renv::restore(confirm = FALSE)'

# copy the SDK
# glob patterns to use conditional copy
COPY --chown=$UID:$GID sr[c]/ap[p]/* ./src/
COPY --chown=$UID:$GID data/ ./data/
COPY --chown=$UID:$GID sdk.R ShinyModule.R .env start-process.sh ./

# shiny port
EXPOSE 3838

ENTRYPOINT ["/bin/bash"]