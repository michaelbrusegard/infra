_: {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      theme = "catppuccin";
      model = "opencode/kimi-k2.5-free";
      small_model = "opencode/gpt-5-nano";
      permission = {
        bash = "allow";
        edit = "allow";
        write = "allow";
        read = "allow";
        grep = "allow";
        glob = "allow";
        list = "allow";
        lsp = "allow";
        patch = "allow";
        todowrite = "allow";
        todoread = "allow";
        webfetch = "allow";
        question = "allow";
      };
      agent = {
        plan = {
          mode = "primary";
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
          tools = {
            write = false;
            edit = false;
          };
          permission = {
            read = {
              "*" = "allow";
              "*.env" = "deny";
              "*.env.*" = "deny";
              "*.env.example" = "allow";
              "*/.ssh/*" = "deny";
              "*/.gnupg/*" = "deny";
              "*credentials*" = "deny";
              "*secrets*" = "deny";
              "*.pem" = "deny";
              "*.key" = "deny";
              "*/.aws/*" = "deny";
              "*/.kube/*" = "deny";
            };
            bash = {
              "*" = "deny";
              "rm *" = "ask";
              "rmdir *" = "ask";
              "mv *" = "ask";
              "chmod *" = "ask";
              "chown *" = "ask";
              "git *" = "ask";
              "git status*" = "allow";
              "git log*" = "allow";
              "git diff*" = "allow";
              "git branch*" = "allow";
              "git show*" = "allow";
              "git stash list*" = "allow";
              "git remote -v" = "allow";
              "git add *" = "allow";
              "git commit *" = "allow";
              "npm *" = "ask";
              "npx *" = "ask";
              "bun *" = "ask";
              "bunx *" = "ask";
              "uv *" = "ask";
              "pip *" = "ask";
              "pip3 *" = "ask";
              "yarn *" = "ask";
              "pnpm *" = "ask";
              "cargo *" = "ask";
              "go *" = "ask";
              "make *" = "ask";
              "dd *" = "deny";
              "mkfs*" = "deny";
              "fdisk *" = "deny";
              "parted *" = "deny";
              "eval *" = "deny";
              "source *" = "deny";
              "curl *|*sh" = "deny";
              "wget *|*sh" = "deny";
              "sudo *" = "deny";
              "su *" = "deny";
              "systemctl *" = "deny";
              "service *" = "deny";
              "shutdown *" = "deny";
              "reboot*" = "deny";
              "init *" = "deny";
              "> /dev/*" = "deny";
              "cat * > /dev/*" = "deny";
            };
          };
        };
        build = {
          mode = "primary";
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
          tools = {
            webfetch = false;
          };
          permission = {
            read = {
              "*" = "allow";
              "*.env" = "deny";
              "*.env.*" = "deny";
              "*.env.example" = "allow";
              "*/.ssh/*" = "deny";
              "*/.gnupg/*" = "deny";
              "*credentials*" = "deny";
              "*secrets*" = "deny";
              "*.pem" = "deny";
              "*.key" = "deny";
              "*/.aws/*" = "deny";
              "*/.kube/*" = "deny";
            };
            bash = {
              "*" = "allow";
              "rm *" = "ask";
              "rmdir *" = "ask";
              "mv *" = "ask";
              "chmod *" = "ask";
              "chown *" = "ask";
              "git *" = "ask";
              "git status*" = "allow";
              "git log*" = "allow";
              "git diff*" = "allow";
              "git branch*" = "allow";
              "git show*" = "allow";
              "git stash list*" = "allow";
              "git remote -v" = "allow";
              "git add *" = "allow";
              "git commit *" = "allow";
              "npm *" = "ask";
              "npx *" = "ask";
              "bun *" = "ask";
              "bunx *" = "ask";
              "uv *" = "ask";
              "pip *" = "ask";
              "pip3 *" = "ask";
              "yarn *" = "ask";
              "pnpm *" = "ask";
              "cargo *" = "ask";
              "go *" = "ask";
              "make *" = "ask";
              "dd *" = "deny";
              "mkfs*" = "deny";
              "fdisk *" = "deny";
              "parted *" = "deny";
              "eval *" = "deny";
              "source *" = "deny";
              "curl *|*sh" = "deny";
              "wget *|*sh" = "deny";
              "sudo *" = "deny";
              "su *" = "deny";
              "systemctl *" = "deny";
              "service *" = "deny";
              "shutdown *" = "deny";
              "reboot*" = "deny";
              "init *" = "deny";
              "> /dev/*" = "deny";
              "cat * > /dev/*" = "deny";
            };
          };
        };
        code-reviewer = {
          description = "Reviews code for best practices and potential issues";
          mode = "subagent";
          model = "opencode/glm-4.7-free";
          temperature = 0.1;
          tools = {
            write = false;
            edit = false;
            bash = false;
          };
          permission = {
            read = {
              "*" = "allow";
              "*.env" = "deny";
              "*.env.*" = "deny";
              "*.env.example" = "allow";
              "*/.ssh/*" = "deny";
              "*/.gnupg/*" = "deny";
              "*credentials*" = "deny";
              "*secrets*" = "deny";
              "*.pem" = "deny";
              "*.key" = "deny";
              "*/.aws/*" = "deny";
              "*/.kube/*" = "deny";
            };
          };
          prompt = ''
            You are in code review mode. Focus on:

            - Code quality and best practices
            - Potential bugs and edge cases
            - Performance implications
            - Security considerations

            Provide constructive feedback without making direct changes.
          '';
        };
        docs-writer = {
          description = "Writes and maintains project documentation";
          mode = "subagent";
          model = "opencode/kimi-k2.5-free";
          temperature = 1.0;
          tools = {
            bash = false;
          };
          permission = {
            read = {
              "*" = "allow";
              "*.env" = "deny";
              "*.env.*" = "deny";
              "*.env.example" = "allow";
              "*/.ssh/*" = "deny";
              "*/.gnupg/*" = "deny";
              "*credentials*" = "deny";
              "*secrets*" = "deny";
              "*.pem" = "deny";
              "*.key" = "deny";
              "*/.aws/*" = "deny";
              "*/.kube/*" = "deny";
            };
          };
          prompt = ''
            You are a technical writer. Create clear, comprehensive documentation.

            Focus on:

            - Clear explanations
            - Proper structure
            - Code examples
            - User-friendly language
          '';
        };
        security-auditor = {
          description = "Performs security audits and identifies vulnerabilities";
          mode = "subagent";
          model = "opencode/glm-4.7-free";
          temperature = 0.3;
          tools = {
            write = false;
            edit = false;
          };
          permission = {
            read = {
              "*" = "allow";
              "*.env" = "deny";
              "*.env.*" = "deny";
              "*.env.example" = "allow";
              "*/.ssh/*" = "deny";
              "*/.gnupg/*" = "deny";
              "*credentials*" = "deny";
              "*secrets*" = "deny";
              "*.pem" = "deny";
              "*.key" = "deny";
              "*/.aws/*" = "deny";
              "*/.kube/*" = "deny";
            };
          };
          prompt = ''
            You are a security expert. Focus on identifying potential security issues.

            Look for:

            - Input validation vulnerabilities
            - Authentication and authorization flaws
            - Data exposure risks
            - Dependency vulnerabilities
            - Configuration security issues
          '';
        };
      };
    };
  };
  home.sessionVariables = {
    OPENCODE_EXPERIMENTAL_OXFMT = "true";
    OPENCODE_EXPERIMENTAL_EXA = "true";
    OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
    OPENCODE_EXPERIMENTAL_MARKDOWN = "true";
    OPENCODE_EXPERIMENTAL_PLAN_MODE = "true";
  };
}
