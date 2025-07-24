# Requirements Gathering Generation

Workflow Stage: Requirements Gathering

First, generate an initial set of requirements in EARS format based on the feature idea, then iterate with the userto refine them until they are complete and accurate.

Don't focus on code exploration in this phase. Instead, just focus on writing requirements which will later be turned into
a design.

**Constraints:**

- The model MUST create a '.claude/specs/{feature_name}/requirements.md' file if it doesn't already exist
- The model MUST generate an initial version of the requirements document based on the user's rough idea WITHOUT asking sequential questions first
- The model MUST format the initial requirements.md document with:
  - A clear introduction section that summarizes the feature
  - A hierarchical numbered list of requirements where each contains:
    - A user story in the format "As a [role], I want [feature], so that [benefit]"
    - A numbered list of acceptance criteria in EARS format (Easy Approach to Requirements Syntax)
  - Example format:
```md
# Requirements Document

## Introduction

[Introduction text here]

## Requirements

### Requirement 1

**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria
This section should have EARS requirements

1. WHEN [event] THEN [system] SHALL [response]
2. IF [precondition] THEN [system] SHALL [response]
  
### Requirement 2

**User Story:** As a [role], I want [feature], so that [benefit]

#### Acceptance Criteria

1. WHEN [event] THEN [system] SHALL [response]
2. WHEN [event] AND [condition] THEN [system] SHALL [response]
```

- The model SHOULD consider edge cases, user experience, technical constraints, and success criteria in the initial requirements
- After updating the requirement document, the model MUST ask the user "Do the requirements look good? If so, we can move on to the design." using the 'userInput' tool.
- The 'userInput' tool MUST be used with the exact string 'spec-requirements-review' as the reason
- The model MUST make modifications to the requirements document if the user requests changes or does not explicitly approve
- The model MUST ask for explicit approval after every iteration of edits to the requirements document
- The model MUST NOT proceed to the design document until receiving clear approval (such as "yes", "approved", "looks good", etc.)
- The model MUST continue the feedback-revision cycle until explicit approval is received
- The model SHOULD suggest specific areas where the requirements might need clarification or expansion
- The model MAY ask targeted questions about specific aspects of the requirements that need clarification
- The model MAY suggest options when the user is unsure about a particular aspect
- The model MUST proceed to the design phase after the user accepts the requirements


# Design Document Creation Generation

Workflow Stage: Design Document Creation

After the user approves the Requirements, you should develop a comprehensive design document based on the feature requirements, conducting necessary research during the design process.
The design document should be based on the requirements document, so ensure it exists first.

**Constraints:**

- The model MUST create a '.claude/specs/{feature_name}/design.md' file if it doesn't already exist
- The model MUST identify areas where research is needed based on the feature requirements
- The model MUST conduct research and build up context in the conversation thread
- The model SHOULD NOTcreate separate research files, but instead use the research as context for the design and implementation plan
- The model MUST summarize key findings that will inform the feature design
- The model SHOULD cite sources and include relevant links in the conversation
- The model MUST create a detailed design document at'.claude/specs/{feature_name}/design.md'
- The model MUST incorporate research findings directly into the design process
- The model MUST include the following sections in the design document:
- Overview
- Architecture
- Components and Interfaces
- Data Models
- Error Handling
- Testing Strategy
- The model SHOULD include diagrams or visual representations when appropriate (use Mermaid for diagrams if applicable)
- The model MUST ensure the design addresses all feature requirements identified during the clarification process
- The model SHOULD highlight design decisions and their rationales
- The model MAY ask the userfor input onspecific technical decisions during the design process
- After updating the design document, the model MUST ask the user "Does the design look good? If so, we can move on to the implementation plan." using the 'userInput' tool.
- The 'userInput' tool MUST be used with the exact string 'spec-design-review'as the reason
- The model MUST make modifications to the design document if the user requests changes or does not explicitly approve
- The model MUST ask for explicit approval after every iteration of edits to the design document
- The model MUST NOT proceed to the implementation plan until receiving clear approval (such as "yes", "approved", "looks good", etc.)
- The model MUST continue the feedback-revision cycle until explicit approval is received
- The model MUST incorporate alluser feedback into the design document before proceeding
- The model MUST offer toreturnto feature requirements clarification if gaps are identified during design

# Implementation Planning Generation

Workflow Stage: Implementation Planning

After the user approves the Design, create an actionable implementation plan with a checklist of coding tasks based on the requirements and design.
The tasks document should be based on the design document, so ensure it exists first.

**Constraints:**

- The model MUST create a '.claude/specs/{feature_name}/tasks.md' file if it doesn't already exist
- The model MUST return to the design step if the user indicates any changes are needed to the design
- The model MUST return to the requirement step if the user indicates that we need additional requirements
- The model MUST create an implementation plan at '.claude/specs/{feature_name}/tasks.md'
- The model MUST use the following specific instructions when creating the implementation plan: Convert the feature design into a series of prompts for a code-generation LLM that will implement each step in a test-driven manner. Prioritize best practices, incremental progress, and early testing, ensuring no big jumps in complexity at any stage. Make sure that each prompt builds on the previous prompts, and ends with wiring things together. There should be no hanging or orphaned code that isn't integrated into a previous step. Focus ONLYon tasks that involve writing, modifying, or testing code.
- The model MUST format the implementation plan as a numbered checkbox list with a maximum of two levels of hierarchy:
- Top-level items (like epics) should be used onlywhen needed
- Sub-tasks should be numbered withdecimal notation (e.g., 1.1, 1.2, 2.1)
-Each item must be a checkbox
- Simple structure is preferred
- The model MUST ensure each task item includes:
- A clear objective as the task description that involves writing, modifying, or testing code
- Additional information as sub-bullets under the task
-Specificreferencesto requirements from the requirements document (referencing granular sub-requirements, not just user stories)
- The model MUST ensure that the implementation plan is a series of discrete, manageable coding steps
- The model MUST ensure each task referencesspecific requirements from the requirement document
- The model MUST NOT include excessive implementation details that are already covered in the design document
- The model MUST assume that all context documents (feature requirements, design) will be available during implementation
- The model MUST ensure each step builds incrementally on previous steps
- The model SHOULD prioritize test-driven development where appropriate
- The model MUST ensure the plan covers all aspects of the design that can be implemented through code
- The model SHOULD sequence steps to validate core functionality early through code
- The model MUST ensure that all requirements are covered by the implementation tasks
- The model MUST offer toreturnto previous steps (requirements or design) if gaps are identified during implementation planning
- The model MUST ONLY include tasks that can be performed by a coding agent (writing code, creating tests, etc.)
- The model MUST NOT include tasks related touser testing, deployment, performance metrics gathering, or other non-coding activities
- The model MUST focus on code implementation tasks that can be executed within the development environment
- The model MUST ensure each task is actionable by a coding agent by following these guidelines:
- Tasks should involve writing, modifying, or testing specific code components
- Tasks should specify what files or components need to be created or modified
- Tasks should be concrete enough that a coding agent can execute them without additional clarification
- Tasks should focus on implementation details rather than high-level concepts
- Tasks should be scoped tospecific coding activities (e.g., "Implement X function" rather than "Support X feature")
- The model MUST explicitly avoid including the following types of non-coding tasks in the implementation plan:
-User acceptance testing oruser feedback gathering
- Deployment to production or staging environments
- Performance metrics gathering or analysis
-Running the application to test endtoend flows. We can however write automated tests to test the endtoendfrom a user perspective.
-User training or documentation creation
- Business process changes or organizational changes
- Marketing or communication activities
-Any task that cannot be completed through writing, modifying, or testing code
- After updating the tasks document, the model MUST ask the user "Do the tasks look good?" using the 'userInput' tool.
- The 'userInput' tool MUST be used with the exact string 'spec-tasks-review'as the reason
- The model MUST make modifications to the tasks document if the user requests changes or does not explicitly approve.
- The model MUST ask for explicit approval after every iteration of edits to the tasks document.
- The model MUST NOT consider the workflow complete until receiving clear approval (such as "yes", "approved", "looks good", etc.).
- The model MUST continue the feedback-revision cycle until explicit approval is received.
- The model MUST stop once the task document has been approved.

**This workflow isONLYfor creating design and planning artifacts. The actual implementation of the feature should be done through a separate workflow.**

- The model MUST NOT attempt to implement the feature as part of this workflow
- The model MUST clearly communicate to the user that this workflow is complete once the design and planning artifacts are created
- The model MUST inform the user that they can begin executing tasks by opening the tasks.md file, and clicking "Start task" next to task items.
