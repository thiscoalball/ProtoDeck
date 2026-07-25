#include <fcntl.h>
#include <libsmbclient.h>
#include <sys/stat.h>

#include <cerrno>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {
std::string g_domain;
std::string g_username;
std::string g_password;

std::string DecodeBase64(const std::string& input) {
  static const std::string chars =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string output;
  int value = 0;
  int bits = -8;
  for (unsigned char c : input) {
    if (c == '=') break;
    const auto index = chars.find(c);
    if (index == std::string::npos) continue;
    value = (value << 6) + static_cast<int>(index);
    bits += 6;
    if (bits >= 0) {
      output.push_back(static_cast<char>((value >> bits) & 0xFF));
      bits -= 8;
    }
  }
  return output;
}

std::string EscapeJson(const std::string& value) {
  std::ostringstream output;
  for (unsigned char c : value) {
    switch (c) {
      case '\\': output << "\\\\"; break;
      case '"': output << "\\\""; break;
      case '\b': output << "\\b"; break;
      case '\f': output << "\\f"; break;
      case '\n': output << "\\n"; break;
      case '\r': output << "\\r"; break;
      case '\t': output << "\\t"; break;
      default:
        if (c < 0x20) {
          output << "\\u00";
          const char* hex = "0123456789abcdef";
          output << hex[(c >> 4) & 0xF] << hex[c & 0xF];
        } else {
          output << c;
        }
    }
  }
  return output.str();
}

void CopyCredential(char* destination, int length, const std::string& value) {
  if (destination == nullptr || length <= 0) return;
  std::snprintf(destination, static_cast<size_t>(length), "%s", value.c_str());
}

void Authenticate(const char*, const char*, char* workgroup, int workgroup_len,
                  char* username, int username_len, char* password,
                  int password_len) {
  CopyCredential(workgroup, workgroup_len, g_domain);
  CopyCredential(username, username_len, g_username);
  CopyCredential(password, password_len, g_password);
}

class SmbContext {
 public:
  SmbContext() : context_(smbc_new_context()) {
    if (context_ == nullptr) return;
    smbc_setFunctionAuthData(context_, Authenticate);
    if (smbc_init_context(context_) == nullptr) {
      smbc_free_context(context_, 1);
      context_ = nullptr;
      return;
    }
    smbc_set_context(context_);
  }

  ~SmbContext() {
    if (context_ == nullptr) return;
    smbc_set_context(nullptr);
    smbc_free_context(context_, 1);
  }

  SmbContext(const SmbContext&) = delete;
  SmbContext& operator=(const SmbContext&) = delete;

  bool valid() const { return context_ != nullptr; }

 private:
  SMBCCTX* context_;
};

std::string EncodePath(const std::string& value) {
  std::ostringstream output;
  const char* hex = "0123456789ABCDEF";
  for (unsigned char c : value) {
    const bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                      (c >= '0' && c <= '9') || c == '-' || c == '_' ||
                      c == '.' || c == '~' || c == '/';
    if (safe) {
      output << c;
    } else {
      output << '%' << hex[(c >> 4) & 0xF] << hex[c & 0xF];
    }
  }
  return output.str();
}

std::string BuildUrl(const std::vector<std::string>& fields,
                     const std::string& path) {
  std::ostringstream output;
  output << "smb://" << fields[1];
  if (!fields[2].empty() && fields[2] != "445") output << ':' << fields[2];
  output << '/' << EncodePath(fields[3]);
  if (!path.empty() && path != "/") {
    if (path.front() != '/') output << '/';
    output << EncodePath(path);
  }
  return output.str();
}

void PrintError(const std::string& operation) {
  std::cout << "{\"ok\":false,\"operation\":\"" << EscapeJson(operation)
            << "\",\"errno\":" << errno << ",\"error\":\""
            << EscapeJson(std::strerror(errno)) << "\"}" << std::endl;
}

bool CopyLocalToRemote(const std::string& local, const std::string& remote,
                       int64_t* total) {
  FILE* input = std::fopen(local.c_str(), "rb");
  if (input == nullptr) return false;
  const int output =
      smbc_open(remote.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (output < 0) {
    std::fclose(input);
    return false;
  }
  char buffer[64 * 1024];
  *total = 0;
  bool ok = true;
  while (true) {
    const size_t read = std::fread(buffer, 1, sizeof(buffer), input);
    if (read == 0) break;
    const ssize_t written = smbc_write(output, buffer, read);
    if (written < 0 || static_cast<size_t>(written) != read) {
      ok = false;
      break;
    }
    *total += written;
  }
  std::fclose(input);
  if (smbc_close(output) < 0) ok = false;
  return ok;
}

bool CopyRemoteToLocal(const std::string& remote, const std::string& local,
                       int64_t* total) {
  const int input = smbc_open(remote.c_str(), O_RDONLY, 0);
  if (input < 0) return false;
  FILE* output = std::fopen(local.c_str(), "wb");
  if (output == nullptr) {
    smbc_close(input);
    return false;
  }
  char buffer[64 * 1024];
  *total = 0;
  bool ok = true;
  while (true) {
    const ssize_t read = smbc_read(input, buffer, sizeof(buffer));
    if (read == 0) break;
    if (read < 0 || std::fwrite(buffer, 1, static_cast<size_t>(read), output) !=
                        static_cast<size_t>(read)) {
      ok = false;
      break;
    }
    *total += read;
  }
  if (smbc_close(input) < 0) ok = false;
  std::fclose(output);
  return ok;
}
}  // namespace

int main() {
  std::vector<std::string> fields;
  std::string line;
  while (fields.size() < 10 && std::getline(std::cin, line)) {
    fields.push_back(DecodeBase64(line));
  }
  if (fields.size() < 10) {
    std::cout << "{\"ok\":false,\"error\":\"invalid request\"}" << std::endl;
    return 2;
  }
  g_username = fields[4];
  g_password = fields[5];
  g_domain = fields[6];
  SmbContext smb_context;
  if (!smb_context.valid()) {
    PrintError("initialize");
    return 1;
  }

  const std::string operation = fields[0];
  const std::string first = BuildUrl(fields, fields[7]);
  if (operation == "connect") {
    const int directory = smbc_opendir(first.c_str());
    if (directory < 0) {
      PrintError(operation);
      return 1;
    }
    smbc_closedir(directory);
    std::cout << "{\"ok\":true}" << std::endl;
    return 0;
  }
  if (operation == "list") {
    const int directory = smbc_opendir(first.c_str());
    if (directory < 0) {
      PrintError(operation);
      return 1;
    }
    std::cout << "{\"ok\":true,\"entries\":[";
    bool first_entry = true;
    while (const struct smbc_dirent* entry = smbc_readdir(directory)) {
      const std::string name = entry->name;
      if (name == "." || name == ".." || name.empty()) continue;
      struct stat status {};
      const std::string child = BuildUrl(
          fields, fields[7] + (fields[7].empty() || fields[7].back() == '/' ? "" : "/") + name);
      const bool has_status = smbc_stat(child.c_str(), &status) == 0;
      const bool directory_entry = entry->smbc_type == SMBC_DIR;
      if (!first_entry) std::cout << ',';
      first_entry = false;
      std::cout << "{\"name\":\"" << EscapeJson(name)
                << "\",\"directory\":" << (directory_entry ? "true" : "false")
                << ",\"size\":" << (has_status ? static_cast<int64_t>(status.st_size) : 0)
                << ",\"modifiedMillis\":"
                << (has_status ? static_cast<int64_t>(status.st_mtime) * 1000 : 0)
                << ",\"attributes\":0}";
    }
    smbc_closedir(directory);
    std::cout << "]}" << std::endl;
    return 0;
  }

  int result = -1;
  int64_t transferred = 0;
  if (operation == "mkdir") result = smbc_mkdir(first.c_str(), 0755);
  if (operation == "deleteFile") result = smbc_unlink(first.c_str());
  if (operation == "deleteDirectory") result = smbc_rmdir(first.c_str());
  if (operation == "rename") {
    result = smbc_rename(first.c_str(), BuildUrl(fields, fields[8]).c_str());
  }
  if (operation == "upload") {
    result = CopyLocalToRemote(fields[8], first, &transferred) ? 0 : -1;
  }
  if (operation == "download") {
    result = CopyRemoteToLocal(first, fields[8], &transferred) ? 0 : -1;
  }
  if (result < 0) {
    PrintError(operation);
    return 1;
  }
  std::cout << "{\"ok\":true,\"bytes\":" << transferred << "}" << std::endl;
  return 0;
}
