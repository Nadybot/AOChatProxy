# Rust syntax target, either x86_64-unknown-linux-musl, aarch64-unknown-linux-musl, arm-unknown-linux-musleabi etc.
ARG RUST_TARGET="x86_64-unknown-linux-musl"
# Musl target, either x86_64-linux-musl, aarch64-linux-musl, arm-linux-musleabi, etc.
ARG MUSL_TARGET="x86_64-linux-musl"
# Final architecture used by dumb-init
# Uses Kernel Naming (aarch64, x86_64, s390x, ppc64le)
ARG FINAL_TARGET="x86_64"

FROM docker.io/library/alpine:edge AS builder
ARG MUSL_TARGET
ARG RUST_TARGET

RUN apk upgrade && \
    apk add curl gcc musl-dev && \
    curl -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y

RUN source $HOME/.cargo/env && \
    if [ "$RUST_TARGET" != $(rustup target list --installed) ]; then \
        rustup target add $RUST_TARGET && \
        curl -L "https://musl.cc/$MUSL_TARGET-cross.tgz" -o /toolchain.tgz && \
        tar xf toolchain.tgz && \
        ln -s "/$MUSL_TARGET-cross/bin/$MUSL_TARGET-gcc" "/usr/bin/$MUSL_TARGET-gcc" && \
        ln -s "/$MUSL_TARGET-cross/bin/$MUSL_TARGET-ld" "/usr/bin/$MUSL_TARGET-ld" && \
        ln -s "/$MUSL_TARGET-cross/bin/$MUSL_TARGET-strip" "/usr/bin/actual-strip"; \
    else \
        echo "skipping toolchain as we are native" && \
        ln -s /usr/bin/strip /usr/bin/actual-strip; \
    fi

WORKDIR /build

COPY Cargo.toml Cargo.lock ./
COPY .cargo ./.cargo/

RUN mkdir src/
RUN echo 'fn main() {}' > ./src/main.rs
RUN source $HOME/.cargo/env && \
    cargo build --release \
        --target="$RUST_TARGET"

RUN rm -f target/$RUST_TARGET/release/deps/aochatproxy*
COPY ./src ./src

RUN source $HOME/.cargo/env && \
    cargo build --release \
        --target="$RUST_TARGET" && \
    cp target/$RUST_TARGET/release/aochatproxy /aochatproxy && \
    actual-strip /aochatproxy

FROM docker.io/library/alpine:edge AS dumb-init
ARG FINAL_TARGET

RUN wget "https://github.com/Yelp/dumb-init/releases/download/v1.2.4/dumb-init_1.2.4_$FINAL_TARGET" -O dumb-init && \
    chmod +x dumb-init

FROM scratch

COPY --from=dumb-init /dumb-init /dumb-init
COPY --from=builder /aochatproxy /aochatproxy

ENTRYPOINT ["./dumb-init", "--"]
CMD ["./aochatproxy"]
