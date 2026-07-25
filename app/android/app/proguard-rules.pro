# SMBJ contains optional Java SE integrations for Expression Language based
# event filtering and Kerberos/GSS authentication. NetTools Android uses
# NTLM/password or Guest authentication and never enters those optional paths.
-dontwarn javax.el.**
-dontwarn org.ietf.jgss.**

# Keep public SMBJ models reached across the Kotlin manager boundary.
-keep class com.hierynomus.smbj.** { *; }
-keep class com.hierynomus.msfscc.** { *; }
-keep class com.hierynomus.msdtyp.** { *; }
-keep class com.hierynomus.mssmb2.** { *; }
