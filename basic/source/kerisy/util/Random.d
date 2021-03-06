/*
 * Kerisy - A high-level D Programming Language Web framework that encourages rapid development and clean, pragmatic design.
 *
 * Copyright (C) 2021, Kerisy.com
 *
 * Website: https://www.kerisy.com
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module kerisy.util.Random;

import std.stdio;
import std.exception;

version (CRuntime_Bionic)
    version = SecureARC4Random; // ChaCha20
version (OSX)
    version = SecureARC4Random; // AES
version (OpenBSD)
    version = SecureARC4Random; // ChaCha20
version (NetBSD)
    version = SecureARC4Random; // ChaCha20

// Insecure arc4random implementations are deliberately not enabled.
// If a cryptographically secure PRNG is not required, they can be used.
//version (CRuntime_UClibc)
//    version = LegacyARC4Random; // ARC4
//version (FreeBSD)
//    version = LegacyARC4Random; // ARC4
//version (DragonFlyBSD)
//    version = LegacyARC4Random; // ARC4
//version (BSD)
//    version = LegacyARC4Random; // Unknown implementation

// ubyte[] getRandom(ushort len = 64)
// {
//     assert(len);
//     ubyte[] buffer;
//     buffer.length = len;
//     version(Windows){
//         HCRYPTPROV hCryptProv;
//         assert(CryptAcquireContext(&hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT) != 0);
//         CryptGenRandom(hCryptProv, cast(DWORD)buffer.length, buffer.ptr);
//         scope(exit)CryptReleaseContext(hCryptProv, 0);
//     }else version(SecureARC4Random){
//         arc4random_buf(buffer.ptr, len);
//     }else{
//         import core.stdc.stdio : FILE, _IONBF, fopen, fclose, fread, setvbuf;
//         auto file = fopen("/dev/urandom","rb");
//         scope(exit)fclose(file);
//         if(file is null)throw new Exception("Failed to open /dev/urandom"); 
//         if(setvbuf(file, null, 0, _IONBF) != 0)throw new 
//             Exception("Failed to disable buffering for random number file handle");
//         if(fread(buffer.ptr, buffer.length, 1, file) != 1)throw new
//             Exception("Failed to read next random number");
//     }
//     return buffer;
// }



version(Windows){
    static if (__VERSION__ >= 2070)
    {
        import core.sys.windows.windows;
    }
    else
    {
        import std.c.windows.windows;
        import std.conv;

    }

    pragma(lib, "advapi32.lib");

    private extern (Windows) nothrow
    {
        alias HCRYPTPROV = size_t;

        enum LPCTSTR NULL = cast(LPCTSTR) 0;
        enum DWORD PROV_RSA_FULL = 1;
        enum DWORD CRYPT_VERIFYCONTEXT = 0xF0000000;

        BOOL CryptAcquireContextA(HCRYPTPROV* phProv, LPCTSTR pszContainer,
                LPCTSTR pszProvider, DWORD dwProvType, DWORD dwFlags);
        alias CryptAcquireContext = CryptAcquireContextA;

        BOOL CryptReleaseContext(HCRYPTPROV hProv, DWORD dwFlags);

        BOOL CryptGenRandom(HCRYPTPROV hProv, DWORD dwLen, BYTE* pbBuffer);
    }
}else version(SecureARC4Random){
    extern(C) @nogc nothrow private @system
    {
        void arc4random_buf(scope void* buf, size_t nbytes);
    }
}
