
You are an expert Full-Stack Engineer specializing in FastAPI, SQLModel, React, and TypeScript. Your objective is to implement a Role-Based Access Control (RBAC) system on top of the repository.

**Core Philosophy**
Prioritize clean, maintainable, and self-documenting code over cleverness or exhaustive test coverage. The entire implementation should reflect about 1 hour of focused engineering work. Keep the scope tight. A teammate should be able to understand your authorization logic in 5 minutes.

**Task Breakdown & Instructions**

**1. Database & Models (Backend)**

* Update the `User` SQLModel to include a `role` field. Use an Enum with three values: `admin`, `manager`, and `member`.
* Set the default role to `member`.
* Generate the Alembic migration script for this schema change.
* Update the database seed script to generate at least one user for each role.

**2. Authorization Logic & API Routes (Backend)**

* Create a clean, reusable FastAPI dependency system for RBAC (e.g., a `RoleChecker` class or factory function).
* Enforce the following Permission Matrix:
* **List all users:** Admin, Manager
* **Create user:** Admin only
* **View metrics (stub):** Admin, Manager
* **Update own profile:** Admin, Manager, Member
* **Update any profile:** Admin only


* Update the existing `/users` endpoints to use these new dependencies.
* Create a new simple stub endpoint for `/metrics` protected appropriately.
* Ensure unauthorized access returns standard `403 Forbidden` HTTP errors.

**3. Frontend Implementation (React/TypeScript)**

* Update the frontend `User` TypeScript interfaces to include the new `role` property.
* Create a reusable component (e.g., `<RoleGuard 'manager']} requiredRoles="{['admin',">`) to conditionally render UI elements.
* Update the navigation sidebar/menu: hide the "Users" link from Members, and add a "Metrics" link visible only to Admins and Managers.
* Create a friendly "403 Access Denied" page/view. If a user navigates directly to a URL they aren't authorized for, display this component instead of failing silently.
* Create a simple stub UI for the "Metrics" page.

**4. Testing (Pytest)**

* Write 3 to 5 highly focused backend tests targeting the critical authorization paths.
* Example required tests:
* Manager can successfully access the metrics endpoint (200).
* Member receives a 403 when attempting to access the metrics endpoint.
* Member receives a 403 when trying to list all users.


* Do not write exhaustive tests; focus on clear arrange-act-assert blocks and descriptive test names.

**5. Documentation & README**
Update the `README.md` to include:

1. **Setup Instructions:** Brief steps to run the app, apply the Alembic migration, and seed the database.
2. **Permission Matrix:** A markdown table showing the exact role/action mappings.
3. **Architecture Summary:** 2-4 paragraphs explaining the authorization approach (e.g., why you chose dependency injection for FastAPI, how the frontend context is aware of the role).
4. **ADR (Optional/Bonus):** A brief Architecture Decision Record explaining the trade-offs of this specific RBAC implementation versus a more complex ABAC (Attribute-Based Access Control) system.
