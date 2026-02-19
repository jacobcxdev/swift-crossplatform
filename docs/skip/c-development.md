<!-- Source: https://skip.dev/docs/c-development/ -->
# C Development Reference

## Overview

One of the advantages of Skip's native mode is the ability to take full advantage of Swift's excellent interoperability with C libraries.

## Native Mode (Fuse)

In Fuse mode, Swift's native C interoperability works directly. Swift can import and call C functions, use C types, and link against C libraries just as it would on any other Swift platform. This is one of the key advantages of native compilation over transpilation.

## Transpiled Mode (Lite)

Skip's `skip-ffi` module enables C interoperability even in transpiled mode, though it is more cumbersome compared to native Swift's direct C support.

## Further Reading

See the Skip blog entry "Sharing C code between Swift and Kotlin for iPhone and Android apps" for deeper learning on utilizing C from transpiled Swift.
