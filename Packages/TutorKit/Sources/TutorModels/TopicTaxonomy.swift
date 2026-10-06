import Foundation

/// Built-in strand › topic taxonomy for GCSE/A-Level Maths and Computer Science.
/// Ids are stable slugs; the app upserts these on launch so user edits to names survive.
public enum TopicTaxonomy {
    public static let version = 1

    public static var builtin: [Topic] {
        var topics: [Topic] = []
        var order = 0
        func strand(_ id: String, _ subject: Subject, _ level: QualificationLevel?, _ name: String, _ children: [(String, String, [String])]) {
            order += 1
            topics.append(Topic(id: id, subject: subject, level: level, name: name, sortOrder: order))
            for (slug, childName, aliases) in children {
                order += 1
                topics.append(Topic(id: "\(id).\(slug)", parentID: id, subject: subject, level: level, name: childName, aliases: aliases, sortOrder: order))
            }
        }

        // GCSE Maths
        strand("maths.number", .maths, .gcse, "Number", [
            ("arithmetic", "Arithmetic & place value", ["Number"]),
            ("fdp", "Fractions, decimals & percentages", ["FDP", "Fractions", "Percentages", "Decimals"]),
            ("ratio", "Ratio & proportion", ["Ratio", "Proportion"]),
            ("indices", "Indices & surds", ["Surds", "Indices", "Powers"]),
            ("standard-form", "Standard form", []),
            ("bounds", "Bounds & accuracy", ["Bounds", "Rounding", "Estimation"]),
            ("primes", "Factors, multiples & primes", ["HCF", "LCM", "Prime factors"]),
        ])
        strand("maths.algebra", .maths, .gcse, "Algebra", [
            ("basics", "Algebra basics & simplifying", ["Algebra basics", "Simplifying"]),
            ("expanding", "Expanding & factorising", ["Expanding", "Factorising"]),
            ("linear", "Linear equations", ["Solving equations"]),
            ("simultaneous", "Simultaneous equations", []),
            ("quadratics", "Quadratics", ["Quadratic equations", "Completing the square", "Quadratic formula"]),
            ("inequalities", "Inequalities", []),
            ("sequences", "Sequences", ["nth term", "Arithmetic sequences"]),
            ("functions", "Functions", ["Composite functions", "Inverse functions"]),
            ("iteration", "Iteration", []),
            ("algebraic-fractions", "Algebraic fractions", []),
            ("proof", "Proof", ["Algebraic proof"]),
            ("rearranging", "Rearranging formulae", ["Changing the subject"]),
        ])
        strand("maths.graphs", .maths, .gcse, "Graphs", [
            ("straight-line", "Straight-line graphs", ["y = mx + c", "Linear graphs"]),
            ("curves", "Quadratic & other graphs", ["Cubic graphs", "Reciprocal graphs"]),
            ("transformations", "Transformations of graphs", []),
            ("real-life", "Real-life & kinematics graphs", ["Distance-time", "Velocity-time"]),
            ("gradients", "Gradients & rates of change", ["Area under a curve"]),
            ("circles", "Equation of a circle", []),
        ])
        strand("maths.geometry", .maths, .gcse, "Geometry & measures", [
            ("angles", "Angles & polygons", ["Angles", "Polygons", "Parallel lines"]),
            ("pythagoras", "Pythagoras", []),
            ("trig", "Trigonometry", ["SOHCAHTOA", "Trig"]),
            ("sine-cosine", "Sine & cosine rules", ["Sine rule", "Cosine rule"]),
            ("circle-theorems", "Circle theorems", []),
            ("vectors", "Vectors", []),
            ("transformations", "Transformations", ["Reflection", "Rotation", "Enlargement", "Translation"]),
            ("constructions", "Constructions & loci", ["Loci", "Constructions"]),
            ("similarity", "Similarity & congruence", ["Similar shapes", "Congruence"]),
            ("area", "Area & perimeter", ["Perimeter", "Area"]),
            ("volume", "Volume & surface area", ["Volume", "Surface area"]),
            ("bearings", "Bearings & scale", ["Bearings", "Scale drawings", "Maps"]),
            ("compound", "Compound measures", ["Speed", "Density", "Pressure"]),
        ])
        strand("maths.statistics", .maths, .gcse, "Probability & statistics", [
            ("probability", "Probability", ["Tree diagrams", "Conditional probability"]),
            ("venn", "Venn diagrams & sets", ["Venn diagrams", "Sets"]),
            ("averages", "Averages & spread", ["Mean", "Median", "Mode", "Range"]),
            ("charts", "Charts & diagrams", ["Pie charts", "Bar charts", "Stem and leaf"]),
            ("scatter", "Scatter graphs", ["Correlation"]),
            ("cumulative", "Cumulative frequency & box plots", ["Box plots", "Cumulative frequency"]),
            ("histograms", "Histograms", []),
            ("sampling", "Sampling", []),
        ])
        strand("maths.problem-solving", .maths, .gcse, "Problem solving", [
            ("multi-step", "Multi-step problems", ["Problem solving"]),
            ("mixed", "Mixed revision", ["Revision"]),
        ])

        // A-Level Maths
        strand("alevel-maths.pure", .maths, .aLevel, "Pure", [
            ("algebra", "Algebra & functions", []),
            ("coordinate", "Coordinate geometry", []),
            ("sequences", "Sequences & series", ["Binomial expansion"]),
            ("trig", "Trigonometry", ["Trig identities", "Radians"]),
            ("exp-log", "Exponentials & logarithms", ["Logs"]),
            ("differentiation", "Differentiation", []),
            ("integration", "Integration", []),
            ("numerical", "Numerical methods", ["Newton-Raphson", "Trapezium rule"]),
            ("vectors", "Vectors", []),
            ("proof", "Proof", ["Proof by contradiction"]),
            ("parametric", "Parametric equations", []),
            ("partial-fractions", "Partial fractions", []),
        ])
        strand("alevel-maths.statistics", .maths, .aLevel, "Statistics", [
            ("sampling", "Sampling & data", ["Large data set"]),
            ("probability", "Probability", []),
            ("distributions", "Distributions", ["Binomial distribution", "Normal distribution"]),
            ("hypothesis", "Hypothesis testing", []),
            ("regression", "Correlation & regression", []),
        ])
        strand("alevel-maths.mechanics", .maths, .aLevel, "Mechanics", [
            ("kinematics", "Kinematics", ["SUVAT"]),
            ("forces", "Forces & Newton's laws", ["Forces"]),
            ("moments", "Moments", []),
            ("projectiles", "Projectiles", []),
            ("friction", "Friction & inclined planes", []),
        ])

        // GCSE Computer Science
        strand("cs.systems", .computerScience, .gcse, "Computer systems", [
            ("architecture", "CPU & architecture", ["Von Neumann", "Fetch-execute cycle"]),
            ("memory", "Memory & storage", ["RAM", "ROM", "Secondary storage"]),
            ("data-rep", "Data representation", ["Binary", "Hexadecimal", "Two's complement", "Character sets", "Images", "Sound"]),
            ("compression", "Compression & encoding", ["Compression"]),
            ("networks", "Networks & protocols", ["Networks", "TCP/IP", "Topologies"]),
            ("security", "Security & threats", ["Cyber security", "Malware", "Encryption"]),
            ("software", "Systems software", ["Operating systems", "Utility software"]),
            ("ethics", "Ethical, legal & environmental", ["Ethics", "Legislation"]),
            ("boolean", "Boolean logic", ["Logic gates", "Truth tables"]),
        ])
        strand("cs.programming", .computerScience, .gcse, "Algorithms & programming", [
            ("algorithms", "Algorithms & computational thinking", ["Decomposition", "Abstraction", "Flowcharts", "Pseudocode"]),
            ("searching", "Searching algorithms", ["Linear search", "Binary search"]),
            ("sorting", "Sorting algorithms", ["Bubble sort", "Merge sort", "Insertion sort"]),
            ("fundamentals", "Programming fundamentals", ["Variables", "Selection", "Iteration", "Data types"]),
            ("data-structures", "Arrays, lists & records", ["Arrays", "2D arrays", "Records"]),
            ("strings", "String handling", []),
            ("subroutines", "Subroutines", ["Functions", "Procedures"]),
            ("files-sql", "File handling & SQL", ["SQL", "Databases"]),
            ("robust", "Robust programs & testing", ["Validation", "Testing", "Defensive design"]),
            ("languages", "Languages, translators & IDEs", ["Compilers", "Interpreters"]),
            ("trace", "Trace tables", []),
        ])

        // A-Level Computer Science
        strand("alevel-cs.theory", .computerScience, .aLevel, "Theory", [
            ("architecture", "Processor architecture", ["Pipelining", "RISC/CISC"]),
            ("os", "Operating systems & software", ["Scheduling", "Virtual memory"]),
            ("data-rep", "Data representation", ["Floating point", "Normalisation"]),
            ("networks", "Networks & the internet", ["Packet switching", "Encryption"]),
            ("databases", "Databases & SQL", ["Normalisation", "ERD", "SQL"]),
            ("data-structures", "Data structures", ["Stacks", "Queues", "Trees", "Graphs", "Hash tables", "Linked lists"]),
            ("algorithms", "Algorithms & complexity", ["Big O", "Dijkstra", "A*", "Sorting", "Searching"]),
            ("theory-of-computation", "Theory of computation", ["Finite state machines", "Turing machines", "Regular expressions", "BNF"]),
            ("boolean", "Boolean algebra", ["Karnaugh maps", "Logic"]),
            ("ethics", "Legal, moral & ethical issues", []),
        ])
        strand("alevel-cs.programming", .computerScience, .aLevel, "Programming", [
            ("paradigms", "Programming paradigms", ["OOP", "Functional programming", "Recursion"]),
            ("oop", "Object-oriented programming", ["Classes", "Inheritance", "Polymorphism"]),
            ("functional", "Functional programming", ["Higher-order functions", "Haskell"]),
            ("recursion", "Recursion", []),
            ("project", "Project & systems development", ["Development methodologies"]),
            ("assembly", "Assembly & low level", ["Little Man Computer", "Assembly"]),
        ])
        return topics
    }

    /// Finds a topic by id, name or alias; strands are allowed too.
    public static func resolve(_ text: String, in topics: [Topic]) -> Topic? {
        topics.first { $0.matches(text) }
    }
}
