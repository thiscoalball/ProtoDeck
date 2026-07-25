package com.nettools.nettools_mobile

import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2CreateOptions
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import java.io.File
import java.util.EnumSet
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal object SmbManager {
    private data class Handle(
        val client: SMBClient,
        val connection: Connection,
        val session: Session,
        val share: DiskShare,
    )

    private val handles = ConcurrentHashMap<String, Handle>()

    fun connect(args: Map<String, Any?>): Map<String, Any?> {
        val host = required(args, "host")
        val shareName = required(args, "share")
        val username = (args["username"] as? String).orEmpty()
        val password = (args["password"] as? String).orEmpty()
        val domain = (args["domain"] as? String).orEmpty()
        val port = ((args["port"] as? Number)?.toInt() ?: 445).coerceIn(1, 65535)
        val client = SMBClient()
        var connection: Connection? = null
        var session: Session? = null
        try {
            connection = client.connect(host, port)
            val auth = if (username.isEmpty()) {
                AuthenticationContext.guest()
            } else {
                AuthenticationContext(username, password.toCharArray(), domain)
            }
            session = connection.authenticate(auth)
            val share = session.connectShare(shareName)
            require(share is DiskShare) { "目标共享不是磁盘共享" }
            val id = UUID.randomUUID().toString()
            handles[id] = Handle(client, connection, session, share)
            return mapOf(
                "sessionId" to id,
                "host" to host,
                "share" to shareName,
                "guest" to session.isGuest,
                "anonymous" to session.isAnonymous,
                "dialect" to connection.negotiatedProtocol.dialect.toString(),
            )
        } catch (error: Throwable) {
            runCatching { session?.close() }
            runCatching { connection?.close() }
            runCatching { client.close() }
            throw error
        }
    }

    fun list(sessionId: String, path: String): List<Map<String, Any?>> {
        val handle = handle(sessionId)
        return handle.share.list(normalize(path))
            .filter { it.fileName != "." && it.fileName != ".." }
            .map { entry ->
                mapOf(
                    "name" to entry.fileName,
                    "directory" to ((entry.fileAttributes and FileAttributes.FILE_ATTRIBUTE_DIRECTORY.value) != 0L),
                    "size" to entry.endOfFile,
                    "modifiedMillis" to entry.lastWriteTime.toEpochMillis(),
                    "attributes" to entry.fileAttributes,
                )
            }
    }

    fun mkdir(sessionId: String, path: String) {
        handle(sessionId).share.mkdir(normalize(path))
    }

    fun delete(sessionId: String, path: String, directory: Boolean) {
        val share = handle(sessionId).share
        if (directory) share.rmdir(normalize(path), false) else share.rm(normalize(path))
    }

    fun rename(sessionId: String, oldPath: String, newPath: String) {
        val handle = handle(sessionId)
        val entry = handle.share.open(
            normalize(oldPath),
            EnumSet.of(AccessMask.DELETE, AccessMask.FILE_READ_ATTRIBUTES),
            EnumSet.noneOf(FileAttributes::class.java),
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OPEN,
            EnumSet.noneOf(SMB2CreateOptions::class.java),
        )
        entry.use { it.rename(normalize(newPath), false) }
    }

    fun upload(sessionId: String, localPath: String, remotePath: String): Long {
        val source = File(localPath)
        require(source.isFile) { "本地文件不存在或不可读取" }
        val remote = handle(sessionId).share.openFile(
            normalize(remotePath),
            EnumSet.of(AccessMask.GENERIC_WRITE),
            EnumSet.of(FileAttributes.FILE_ATTRIBUTE_NORMAL),
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OVERWRITE_IF,
            EnumSet.of(SMB2CreateOptions.FILE_NON_DIRECTORY_FILE),
        )
        remote.use { target ->
            source.inputStream().use { input ->
                target.outputStream.use { output -> input.copyTo(output) }
            }
        }
        return source.length()
    }

    fun download(sessionId: String, remotePath: String, localPath: String): Long {
        val destination = File(localPath)
        destination.parentFile?.mkdirs()
        val remote = handle(sessionId).share.openFile(
            normalize(remotePath),
            EnumSet.of(AccessMask.GENERIC_READ),
            EnumSet.noneOf(FileAttributes::class.java),
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OPEN,
            EnumSet.of(SMB2CreateOptions.FILE_NON_DIRECTORY_FILE),
        )
        try {
            remote.use { source ->
                source.inputStream.use { input ->
                    destination.outputStream().use { output -> input.copyTo(output) }
                }
            }
            return destination.length()
        } catch (error: Throwable) {
            runCatching { destination.delete() }
            throw error
        }
    }

    fun disconnect(sessionId: String): Boolean {
        val handle = handles.remove(sessionId) ?: return false
        runCatching { handle.share.close() }
        runCatching { handle.session.close() }
        runCatching { handle.connection.close() }
        runCatching { handle.client.close() }
        return true
    }

    private fun handle(sessionId: String): Handle =
        handles[sessionId] ?: throw IllegalStateException("SMB 会话已断开")

    private fun normalize(path: String): String = path
        .trim().replace('/', '\\').trimStart('\\').trimEnd('\\')

    private fun required(args: Map<String, Any?>, key: String): String =
        (args[key] as? String)?.trim().takeUnless { it.isNullOrEmpty() }
            ?: throw IllegalArgumentException("$key 不能为空")
}
