# ISC Log Reader

A helper script to read and format JSON log entries from `ccg.log` with timestamps, log levels, messages, and exceptions (including stacktraces if available).

---

## 📌 Installation

Save the script inside: `/home/sailpoint/log/`

Make it executable:

    chmod +x /home/sailpoint/log/isc_log_reader.sh

---

## ▶️ Usage

Whenever you need to read the last logs, run:

    cd /home/sailpoint/log/ && tail -n20 ccg.log > temp.log && ./isc_log_reader.sh temp.log

---

## ⚙️ Options

You can control stacktrace printing with the environment variable `PRINT_STACK`:

- `PRINT_STACK=all` → prints the full stacktrace  
- `PRINT_STACK=1`   → prints only the first line (default)  
- `PRINT_STACK=0`   → disables stacktrace printing

Example:

    PRINT_STACK=all ./isc_log_reader.sh temp.log

---

## 🔧 Dependencies

- `jq` must be installed. Install on Debian/Ubuntu with:

    sudo apt-get install jq -y

---

## 📂 Example Output

    [2025-09-11 15:42:30,123] [+00d 00h 00m 05s] [ERROR] Exception (NullPointerException): Something went wrong
    [2025-09-11 15:42:30,123] [+00d 00h 00m 05s] [ERROR] at com.example.MyClass.method(MyClass.java:42)

---

## 📝 Notes

- Default log location: `/home/sailpoint/log/ccg.log`  
- Temporary file used: `temp.log`  
- Only JSON-formatted lines are parsed.
