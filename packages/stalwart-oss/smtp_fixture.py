"""Small native-mail fixture helpers shared by isolated SMTP exercises.

No edge routing, recipient policy, authentication bridge or live endpoint setup.
Callers own namespace isolation and supply disposable native clients/fixtures.
"""

from integration import require


def change(client, kind, ident, values):
    return client.jmap(f"x:{kind}/set", {"update": {ident: values}})


def query(client, kind):
    return client.jmap(f"x:{kind}/query", {})["ids"]


def objects(client, kind):
    return client.jmap(f"x:{kind}/get", {"ids": query(client, kind)})["list"]


def email_ids(client, account_id):
    response = client.expect(
        "POST",
        "/jmap",
        200,
        {
            "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
            "methodCalls": [["Email/query", {"accountId": account_id}, "mail-fixture"]],
        },
        auth="recovery",
    )
    calls = response.document()["methodResponses"]
    require(
        len(calls) == 1
        and calls[0][0] == "Email/query"
        and calls[0][2] == "mail-fixture",
        "Unexpected Email/query response",
    )
    return calls[0][1]["ids"]
