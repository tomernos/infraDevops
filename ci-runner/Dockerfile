# Ephemeral GitHub Actions runner image for Android (React Native) builds.
#
# Runs as a Cloud Run Job: one execution = one JIT (just-in-time) ephemeral runner
# that picks up exactly one queued job, builds, uploads artifacts, then exits.
#
# Base = the official GitHub Actions runner agent. We layer the Android toolchain
# on top so it mirrors (and out-resources) the GitHub-hosted Android environment.
#
# Build/push via ci-runner/cloudbuild.yaml (Cloud Build → Artifact Registry).

FROM ghcr.io/actions/actions-runner:2.323.0

# ── system tooling (root) ─────────────────────────────────────────────────────
USER root

ARG NODE_MAJOR=20
ARG NDK_VERSION=27.0.12077973
ARG ANDROID_PLATFORM=android-35
ARG BUILD_TOOLS=35.0.0
ARG CMDLINE_TOOLS_VERSION=11076708

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        unzip curl git ca-certificates \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# ── Android SDK + NDK ─────────────────────────────────────────────────────────
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${NDK_VERSION}
ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;${ANDROID_PLATFORM}" \
        "build-tools;${BUILD_TOOLS}" \
        "ndk;${NDK_VERSION}" >/dev/null \
    && chown -R runner:runner "${ANDROID_HOME}"

# ── entrypoint: register a JIT ephemeral runner, run one job, exit ────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
