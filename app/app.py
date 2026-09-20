"""Residency requirements editor."""
import logging

import dash
import dash_ag_grid as dag
from dash import Input, Output, State, callback, dcc, html, no_update

import db

log = logging.getLogger(__name__)

app = dash.Dash(__name__, title="Residency Requirements")
server = app.server  # gunicorn entrypoint

COLUMNS = [
    {"field": "id", "headerName": "ID", "width": 90, "editable": False,
     "checkboxSelection": True},
    {"field": "country_name", "headerName": "Country", "width": 140, "editable": False},
    {"field": "document_name", "headerName": "Document", "flex": 2,
     "minWidth": 220},
    {"field": "description", "headerName": "Description", "flex": 3,
     "cellEditor": "agLargeTextCellEditor", "cellEditorPopup": True,
     "wrapText": True,
     # AG Grid sets line-height to the row height, so wrapped lines are far
     # too tall to fit; override it or only the first line is visible.
     "cellStyle": {"lineHeight": "1.4", "whiteSpace": "normal",
                   "display": "flex", "alignItems": "center"}},
    {"field": "mandatory", "headerName": "Mandatory", "width": 130,
     "cellRenderer": "agCheckboxCellRenderer",
     "cellEditor": "agCheckboxCellEditor"},
]

app.layout = html.Div(
    style={"width": "96vw", "maxWidth": "1800px", "margin": "1.5rem auto",
           "fontFamily": "system-ui"},
    children=[
        html.H2("Residency requirements"),
        html.P("Documents required for permanent residence. Click a cell to edit; "
               "changes save immediately.",
               style={"color": "#555"}),
        html.Div(
            style={"display": "flex", "gap": "0.75rem", "alignItems": "center",
                   "marginBottom": "0.75rem"},
            children=[
                dcc.Dropdown(id="country", options=[], placeholder="All countries",
                             style={"width": "260px"}),
                html.Button("Add row", id="add", n_clicks=0),
                html.Button("Delete selected", id="delete", n_clicks=0),
                html.Span(id="status", style={"color": "#555", "marginLeft": "auto"}),
            ],
        ),
        dag.AgGrid(
            id="grid",
            columnDefs=COLUMNS,
            rowData=[],
            defaultColDef={"editable": True, "sortable": True, "resizable": True},
            dashGridOptions={"rowSelection": "multiple", "animateRows": True,
                             "rowHeight": 56},
            style={"height": "520px"},
        ),
        dcc.Interval(id="boot", interval=100, max_intervals=1),
    ],
)


@callback(Output("country", "options"), Input("boot", "n_intervals"))
def load_countries(_):
    return [{"label": f"{c['country_name']} ({c['country_alpha2']})", "value": c["id"]}
            for c in db.countries()]


@callback(
    Output("grid", "rowData"),
    Output("status", "children"),
    Input("boot", "n_intervals"),
    Input("country", "value"),
    Input("grid", "cellValueChanged"),
    Input("add", "n_clicks"),
    Input("delete", "n_clicks"),
    State("grid", "selectedRows"),
    prevent_initial_call=False,
)
def sync(_boot, country_id, changed, _add, _del, selected):
    trigger = dash.ctx.triggered_id
    try:
        if trigger == "grid" and changed:
            change = changed[0]
            db.update_field(change["data"]["id"], change["colId"], change["value"])
            note = f"Saved {change['colId']}"
        elif trigger == "add":
            if not country_id:
                return no_update, "Pick a country before adding a row"
            db.add(country_id)
            note = "Row added"
        elif trigger == "delete":
            ids = [r["id"] for r in (selected or [])]
            if not ids:
                return no_update, "Nothing selected"
            db.delete(ids)
            note = f"Deleted {len(ids)} row(s)"
        else:
            note = ""
        return db.requirements(country_id), note
    except Exception as exc:  # surface failures instead of silently not saving
        log.exception("action %s failed", trigger)
        return no_update, f"Error: {exc}"


if __name__ == "__main__":
    app.run(debug=True, port=8050)
