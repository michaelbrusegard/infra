#!/usr/bin/env python3
"""Context-efficient, allowlisted CLI for the private Mealie instance."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


MEAL_TYPES = ("breakfast", "lunch", "dinner", "side", "snack", "drink", "dessert")
MISSING = object()


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_text(value: Any) -> str:
    text = str(value)
    token = os.environ.get("MEALIE_API_TOKEN", "")
    if token:
        text = text.replace(token, "[REDACTED]")
    return text[:500]


def load_object(value: str | None, label: str = "--data") -> dict[str, Any]:
    if value is None:
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} must be valid JSON: {exc.msg}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{label} must contain a JSON object")
    return parsed


def read_import_data(args: argparse.Namespace) -> str:
    if args.file:
        try:
            with open(args.file, encoding="utf-8") as source:
                return source.read(5_000_001)
        except OSError as exc:
            raise ValueError(f"unable to read import file: {exc}") from exc
    return args.data


class MealieClient:
    def __init__(self) -> None:
        self.base_url = os.environ.get(
            "MEALIE_URL", "http://mealie.mealie.svc.cluster.local:9000"
        ).rstrip("/")
        self.token = os.environ.get("MEALIE_API_TOKEN", "").strip()
        if not self.token:
            raise RuntimeError("MEALIE_API_TOKEN is not configured")

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: Any = MISSING,
        raw_data: bytes | None = None,
        content_type: str | None = None,
    ) -> Any:
        url = f"{self.base_url}{path}"
        if query:
            values = {key: value for key, value in query.items() if value is not None}
            if values:
                url += "?" + urlencode(values, doseq=True)
        if raw_data is not None and body is not MISSING:
            raise ValueError("a request cannot contain JSON and raw data")
        data = (
            raw_data
            if raw_data is not None
            else (None if body is MISSING else json.dumps(body).encode())
        )
        request = Request(
            url,
            data=data,
            method=method,
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {self.token}",
                **(
                    {"Content-Type": content_type or "application/json"}
                    if data is not None
                    else {}
                ),
            },
        )
        try:
            with urlopen(request, timeout=45) as response:
                payload = response.read()
                status = response.status
        except HTTPError as exc:
            payload = exc.read(4096)
            detail = self._decode(payload)
            raise RuntimeError(
                f"Mealie returned HTTP {exc.code}: {safe_text(detail)}"
            ) from exc
        except URLError as exc:
            raise RuntimeError(
                f"unable to reach Mealie: {safe_text(exc.reason)}"
            ) from exc
        if not payload:
            return {"ok": True, "status": status}
        return self._decode(payload)

    @staticmethod
    def _decode(payload: bytes) -> Any:
        text = payload.decode("utf-8", errors="replace")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"text": text[:4096]}

    def get(self, path: str, query: dict[str, Any] | None = None) -> Any:
        return self.request("GET", path, query=query)

    def post(self, path: str, body: Any) -> Any:
        return self.request("POST", path, body=body)

    def put(self, path: str, body: Any) -> Any:
        return self.request("PUT", path, body=body)

    def post_archive(self, path: str, filename: str) -> Any:
        try:
            with open(filename, "rb") as archive:
                content = archive.read(100_000_001)
        except OSError as exc:
            raise ValueError(f"unable to read archive: {exc}") from exc
        if len(content) > 100_000_000:
            raise ValueError("archive exceeds the 100 MB limit")
        boundary = f"----hermes-mealie-{secrets.token_hex(16)}"
        safe_name = (
            os.path.basename(filename)
            .replace('"', "_")
            .replace("\r", "_")
            .replace("\n", "_")
        )
        data = (
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="archive"; filename="{safe_name}"\r\n'
                "Content-Type: application/zip\r\n\r\n"
            ).encode()
            + content
            + f"\r\n--{boundary}--\r\n".encode()
        )
        return self.request(
            "POST",
            path,
            raw_data=data,
            content_type=f"multipart/form-data; boundary={boundary}",
        )

    def delete(self, path: str) -> Any:
        return self.request("DELETE", path)


def encoded(value: str) -> str:
    return quote(value, safe="")


def paging(args: argparse.Namespace) -> dict[str, Any]:
    return {"page": args.page, "perPage": args.limit}


def require_confirmation(args: argparse.Namespace, resource: str) -> None:
    if not args.yes:
        raise ValueError(f"deleting {resource} requires --yes")


def recipe_changes(args: argparse.Namespace, *, allow_name: bool) -> dict[str, Any]:
    changes = load_object(args.data)
    fields = {
        "description": args.description,
        "recipeServings": args.servings,
        "recipeYield": args.yield_text,
        "prepTime": args.prep_time,
        "cookTime": args.cook_time,
        "totalTime": args.total_time,
    }
    if allow_name:
        fields["name"] = args.name
    changes.update({key: value for key, value in fields.items() if value is not None})
    if args.ingredient is not None:
        changes["recipeIngredient"] = [
            {"display": item, "originalText": item} for item in args.ingredient
        ]
    if args.instruction is not None:
        changes["recipeInstructions"] = [{"text": item} for item in args.instruction]
    return changes


def update_recipe(client: MealieClient, slug: str, changes: dict[str, Any]) -> Any:
    recipe = client.get(f"/api/recipes/{encoded(slug)}")
    if not isinstance(recipe, dict):
        raise RuntimeError("Mealie returned an invalid recipe")
    recipe.update(changes)
    return client.put(f"/api/recipes/{encoded(slug)}", recipe)


def request_for(args: argparse.Namespace, client: MealieClient) -> Any:
    command = args.command
    if command == "status":
        user = client.get("/api/users/self")
        if not isinstance(user, dict):
            return user
        return {
            "authenticated": True,
            "id": user.get("id"),
            "email": user.get("email"),
            "fullName": user.get("fullName"),
            "admin": user.get("admin"),
        }
    if command == "recipes":
        query = paging(args)
        query.update(
            {
                "search": args.search,
                "orderBy": args.order_by,
                "orderDirection": args.direction,
            }
        )
        return client.get("/api/recipes", query)
    if command == "recipe":
        return client.get(f"/api/recipes/{encoded(args.slug)}")
    if command == "recipe-create":
        slug = client.post("/api/recipes", {"name": args.name})
        if not isinstance(slug, str):
            raise RuntimeError("Mealie did not return the new recipe slug")
        changes = recipe_changes(args, allow_name=False)
        if changes:
            return update_recipe(client, slug, changes)
        return client.get(f"/api/recipes/{encoded(slug)}")
    if command == "recipe-edit":
        changes = recipe_changes(args, allow_name=True)
        if not changes:
            raise ValueError("recipe-edit requires at least one change")
        return update_recipe(client, args.slug, changes)
    if command == "recipe-delete":
        require_confirmation(args, "a recipe")
        return client.delete(f"/api/recipes/{encoded(args.slug)}")
    if command == "import-url":
        return client.post(
            "/api/recipes/create/url",
            {
                "url": args.url,
                "includeTags": args.include_tags,
                "includeCategories": args.include_categories,
            },
        )
    if command == "import-urls":
        return client.post(
            "/api/recipes/create/url/bulk",
            {"imports": [{"url": url} for url in args.urls]},
        )
    if command == "import-raw":
        data = read_import_data(args)
        if len(data) > 5_000_000:
            raise ValueError("import data exceeds the 5 MB limit")
        return client.post(
            "/api/recipes/create/html-or-json",
            {
                "data": data,
                "url": args.source_url,
                "includeTags": args.include_tags,
                "includeCategories": args.include_categories,
            },
        )
    if command == "import-zip":
        return client.post_archive("/api/recipes/create/zip", args.file)
    if command == "mealplans":
        query = paging(args)
        query.update({"start_date": args.start, "end_date": args.end})
        return client.get("/api/households/mealplans", query)
    if command == "mealplan-today":
        return client.get("/api/households/mealplans/today")
    if command == "mealplan":
        return client.get(f"/api/households/mealplans/{args.id}")
    if command == "mealplan-add":
        return client.post(
            "/api/households/mealplans",
            {
                "date": args.date,
                "entryType": args.type,
                "title": args.title,
                "text": args.text,
                "recipeId": args.recipe_id,
            },
        )
    if command == "mealplan-edit":
        current = client.get(f"/api/households/mealplans/{args.id}")
        if not isinstance(current, dict):
            raise RuntimeError("Mealie returned an invalid meal-plan entry")
        body = {
            key: current.get(key)
            for key in (
                "date",
                "entryType",
                "title",
                "text",
                "recipeId",
                "id",
                "groupId",
                "userId",
            )
        }
        changes = load_object(args.data)
        changes.update(
            {
                key: value
                for key, value in {
                    "date": args.date,
                    "entryType": args.type,
                    "title": args.title,
                    "text": args.text,
                    "recipeId": args.recipe_id,
                }.items()
                if value is not None
            }
        )
        if not changes:
            raise ValueError("mealplan-edit requires at least one change")
        body.update(changes)
        return client.put(f"/api/households/mealplans/{args.id}", body)
    if command == "mealplan-delete":
        require_confirmation(args, "a meal-plan entry")
        return client.delete(f"/api/households/mealplans/{args.id}")
    if command == "shopping-lists":
        return client.get("/api/households/shopping/lists", paging(args))
    if command == "shopping-list":
        return client.get(f"/api/households/shopping/lists/{encoded(args.id)}")
    if command == "shopping-list-add":
        return client.post("/api/households/shopping/lists", {"name": args.name})
    if command == "shopping-list-edit":
        current = client.get(f"/api/households/shopping/lists/{encoded(args.id)}")
        if not isinstance(current, dict):
            raise RuntimeError("Mealie returned an invalid shopping list")
        body = {
            key: current.get(key)
            for key in (
                "name",
                "extras",
                "createdAt",
                "update_at",
                "groupId",
                "userId",
                "id",
                "listItems",
            )
        }
        changes = load_object(args.data)
        if args.name is not None:
            changes["name"] = args.name
        if not changes:
            raise ValueError("shopping-list-edit requires at least one change")
        body.update(changes)
        return client.put(f"/api/households/shopping/lists/{encoded(args.id)}", body)
    if command == "shopping-list-delete":
        require_confirmation(args, "a shopping list")
        return client.delete(f"/api/households/shopping/lists/{encoded(args.id)}")
    if command == "shopping-items":
        return client.get("/api/households/shopping/items", paging(args))
    if command == "shopping-item":
        return client.get(f"/api/households/shopping/items/{encoded(args.id)}")
    if command == "shopping-item-add":
        return client.post(
            "/api/households/shopping/items",
            {
                "shoppingListId": args.list_id,
                "display": args.display,
                "quantity": args.quantity,
                "note": args.note,
                "checked": False,
            },
        )
    if command in {"shopping-item-edit", "shopping-item-check"}:
        current = client.get(f"/api/households/shopping/items/{encoded(args.id)}")
        if not isinstance(current, dict):
            raise RuntimeError("Mealie returned an invalid shopping-list item")
        allowed = (
            "quantity",
            "unit",
            "food",
            "referencedRecipe",
            "note",
            "display",
            "shoppingListId",
            "checked",
            "position",
            "foodId",
            "labelId",
            "unitId",
            "extras",
            "recipeReferences",
        )
        body = {key: current.get(key) for key in allowed if key in current}
        if command == "shopping-item-check":
            body["checked"] = not args.undo
        else:
            changes = load_object(args.data)
            changes.update(
                {
                    key: value
                    for key, value in {
                        "display": args.display,
                        "quantity": args.quantity,
                        "note": args.note,
                    }.items()
                    if value is not None
                }
            )
            if args.checked is not None:
                changes["checked"] = args.checked == "true"
            if not changes:
                raise ValueError("shopping-item-edit requires at least one change")
            body.update(changes)
        return client.put(f"/api/households/shopping/items/{encoded(args.id)}", body)
    if command == "shopping-item-delete":
        require_confirmation(args, "a shopping-list item")
        return client.delete(f"/api/households/shopping/items/{encoded(args.id)}")
    if command == "shopping-add-recipe":
        return client.post(
            f"/api/households/shopping/lists/{encoded(args.list_id)}/recipe",
            [{"recipeId": args.recipe_id, "recipeIncrementQuantity": args.scale}],
        )
    raise ValueError(f"unsupported command: {command}")


def add_paging(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--page", type=int, default=1)
    parser.add_argument(
        "--limit", type=int, choices=range(1, 101), default=20, metavar="1..100"
    )


def add_recipe_fields(parser: argparse.ArgumentParser, *, include_name: bool) -> None:
    if include_name:
        parser.add_argument("--name")
    parser.add_argument("--description")
    parser.add_argument("--servings", type=float)
    parser.add_argument("--yield-text")
    parser.add_argument("--prep-time", help="ISO 8601 duration, for example PT15M")
    parser.add_argument("--cook-time", help="ISO 8601 duration, for example PT30M")
    parser.add_argument("--total-time", help="ISO 8601 duration, for example PT45M")
    parser.add_argument(
        "--ingredient",
        action="append",
        help="replace ingredients; repeat for each line",
    )
    parser.add_argument(
        "--instruction",
        action="append",
        help="replace instructions; repeat for each step",
    )
    parser.add_argument(
        "--data", help="additional Recipe-Input fields as a JSON object"
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        prog="mealie",
        description="Manage recipes, meal plans, and shopping lists through an allowlisted CLI.",
    )
    sub = root.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="verify authentication without exposing the token")

    recipes = sub.add_parser("recipes", help="list or search recipes")
    recipes.add_argument("--search")
    recipes.add_argument("--order-by", default="dateUpdated")
    recipes.add_argument("--direction", choices=("asc", "desc"), default="desc")
    add_paging(recipes)
    recipe = sub.add_parser("recipe", help="get one complete recipe")
    recipe.add_argument("slug")
    create = sub.add_parser("recipe-create", help="create a complete manual recipe")
    create.add_argument("name")
    add_recipe_fields(create, include_name=False)
    edit = sub.add_parser(
        "recipe-edit", help="edit a recipe while preserving server fields"
    )
    edit.add_argument("slug")
    add_recipe_fields(edit, include_name=True)
    delete = sub.add_parser("recipe-delete", help="delete a recipe")
    delete.add_argument("slug")
    delete.add_argument("--yes", action="store_true")

    import_url = sub.add_parser("import-url", help="import one recipe from a URL")
    import_url.add_argument("url")
    import_url.add_argument("--include-tags", action="store_true")
    import_url.add_argument("--include-categories", action="store_true")
    import_urls = sub.add_parser("import-urls", help="queue imports for multiple URLs")
    import_urls.add_argument("urls", nargs="+")
    import_raw = sub.add_parser("import-raw", help="import schema.org JSON or HTML")
    source = import_raw.add_mutually_exclusive_group(required=True)
    source.add_argument("--data")
    source.add_argument("--file")
    import_raw.add_argument("--source-url")
    import_raw.add_argument("--include-tags", action="store_true")
    import_raw.add_argument("--include-categories", action="store_true")
    import_zip = sub.add_parser("import-zip", help="import a Mealie recipe archive")
    import_zip.add_argument("file")

    mealplans = sub.add_parser("mealplans", help="list meal-plan entries")
    mealplans.add_argument("--start", help="YYYY-MM-DD")
    mealplans.add_argument("--end", help="YYYY-MM-DD")
    add_paging(mealplans)
    sub.add_parser("mealplan-today", help="get today's meal-plan entries")
    mealplan = sub.add_parser("mealplan", help="get one meal-plan entry")
    mealplan.add_argument("id", type=int)
    plan_add = sub.add_parser("mealplan-add", help="add a meal-plan entry")
    plan_add.add_argument("date", help="YYYY-MM-DD")
    plan_add.add_argument("--type", choices=MEAL_TYPES, default="dinner")
    plan_add.add_argument("--title", default="")
    plan_add.add_argument("--text", default="")
    plan_add.add_argument("--recipe-id")
    plan_edit = sub.add_parser("mealplan-edit", help="edit a meal-plan entry")
    plan_edit.add_argument("id", type=int)
    plan_edit.add_argument("--date")
    plan_edit.add_argument("--type", choices=MEAL_TYPES)
    plan_edit.add_argument("--title")
    plan_edit.add_argument("--text")
    plan_edit.add_argument("--recipe-id")
    plan_edit.add_argument("--data", help="additional UpdatePlanEntry fields as JSON")
    plan_delete = sub.add_parser("mealplan-delete", help="delete a meal-plan entry")
    plan_delete.add_argument("id", type=int)
    plan_delete.add_argument("--yes", action="store_true")

    lists = sub.add_parser("shopping-lists", help="list shopping lists")
    add_paging(lists)
    shopping_list = sub.add_parser("shopping-list", help="get a list and its items")
    shopping_list.add_argument("id")
    list_add = sub.add_parser("shopping-list-add", help="create a shopping list")
    list_add.add_argument("name")
    list_edit = sub.add_parser("shopping-list-edit", help="edit a shopping list")
    list_edit.add_argument("id")
    list_edit.add_argument("--name")
    list_edit.add_argument(
        "--data", help="additional ShoppingListUpdate fields as JSON"
    )
    list_delete = sub.add_parser("shopping-list-delete", help="delete a shopping list")
    list_delete.add_argument("id")
    list_delete.add_argument("--yes", action="store_true")

    items = sub.add_parser("shopping-items", help="list shopping-list items")
    add_paging(items)
    item = sub.add_parser("shopping-item", help="get one shopping-list item")
    item.add_argument("id")
    item_add = sub.add_parser(
        "shopping-item-add", help="add an item to a shopping list"
    )
    item_add.add_argument("list_id")
    item_add.add_argument("display")
    item_add.add_argument("--quantity", type=float, default=1)
    item_add.add_argument("--note", default="")
    item_edit = sub.add_parser("shopping-item-edit", help="edit a shopping-list item")
    item_edit.add_argument("id")
    item_edit.add_argument("--display")
    item_edit.add_argument("--quantity", type=float)
    item_edit.add_argument("--note")
    item_edit.add_argument("--checked", choices=("true", "false"))
    item_edit.add_argument(
        "--data", help="additional ShoppingListItemUpdate fields as JSON"
    )
    item_check = sub.add_parser("shopping-item-check", help="check or uncheck an item")
    item_check.add_argument("id")
    item_check.add_argument("--undo", action="store_true")
    item_delete = sub.add_parser(
        "shopping-item-delete", help="delete a shopping-list item"
    )
    item_delete.add_argument("id")
    item_delete.add_argument("--yes", action="store_true")
    add_recipe = sub.add_parser(
        "shopping-add-recipe", help="add a recipe's ingredients to a list"
    )
    add_recipe.add_argument("list_id")
    add_recipe.add_argument("recipe_id")
    add_recipe.add_argument("--scale", type=float, default=1)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        if hasattr(args, "page") and args.page < 1:
            raise ValueError("--page must be at least 1")
        compact(request_for(args, MealieClient()))
        return 0
    except (ValueError, RuntimeError) as exc:
        print(f"mealie: {safe_text(exc)}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(
            f"mealie: request failed: {type(exc).__name__}: {safe_text(exc)}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
