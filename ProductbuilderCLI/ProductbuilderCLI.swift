import Foundation

@main
enum ProductbuilderCLI {
    enum CLIError: LocalizedError {
        case helpRequested
        case invalidArguments(String)
        case unreadableProject(String)

        var errorDescription: String? {
            switch self {
            case .helpRequested:
                return nil
            case .invalidArguments(let message):
                return message
            case .unreadableProject(let path):
                return "Unable to read project: \(path)"
            }
        }
    }

    struct Options {
        var projectPath: String
        var outputDirectory: String?
    }

    static func main() async {
        do {
            let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            var project = try loadProject(at: options.projectPath)

            if let outputDirectory = options.outputDirectory {
                project.outputDirectory = expandedPath(outputDirectory)
            }

            let result = try await PackageBuildService().build(project: project) { message in
                print(message)
            }

            print("Output: \(result.outputURL.path)")
            if let uninstallerURL = result.uninstallerURL {
                print("Uninstaller: \(uninstallerURL.path)")
            }
            exit(EXIT_SUCCESS)
        } catch {
            if case CLIError.helpRequested = error {
                print(usage)
                exit(EXIT_SUCCESS)
            }
            fputs("productbuilder: \(error.localizedDescription)\n\n", stderr)
            fputs(usage, stderr)
            exit(EXIT_FAILURE)
        }
    }

    static let usage = """
    Usage:
      productbuilder build <project.json> [--output <directory>]
      productbuilder -build <project.json> [-output <directory>]

    Options:
      -o, --output, -output   Override the output directory stored in the project.
      -h, --help              Show this help.

    """

    static func parseArguments(_ arguments: [String]) throws -> Options {
        guard !arguments.contains("-h"), !arguments.contains("--help") else {
            throw CLIError.helpRequested
        }
        guard !arguments.isEmpty else {
            throw CLIError.invalidArguments("Missing command.")
        }

        var index = 0
        let command = arguments[index]
        guard command == "build" || command == "-build" || command == "--build" else {
            throw CLIError.invalidArguments("Unknown command: \(command)")
        }
        index += 1

        guard index < arguments.count else {
            throw CLIError.invalidArguments("Missing project path.")
        }

        let projectPath = expandedPath(arguments[index])
        index += 1

        var outputDirectory: String?
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "-o", "--output", "-output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.invalidArguments("Missing value for \(option).")
                }
                outputDirectory = arguments[index]
                index += 1
            default:
                throw CLIError.invalidArguments("Unknown option: \(option)")
            }
        }

        return Options(projectPath: projectPath, outputDirectory: outputDirectory)
    }

    static func loadProject(at path: String) throws -> PackageProject {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.unreadableProject(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(PackageProject.self, from: data)
    }

    static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
