-- ----
-- Extra commands to run after the tables are created, loaded,
-- indexes built and extra's created.
-- PostgreSQL version.
-- ----
analyze table bmsql_warehouse compute statistics;
analyze table bmsql_district compute statistics;
analyze table bmsql_customer compute statistics;
analyze table bmsql_oorder compute statistics;
analyze table bmsql_new_order compute statistics;
analyze table bmsql_order_line compute statistics;
analyze table bmsql_stock compute statistics;
analyze table bmsql_item compute statistics;
analyze table bmsql_history compute statistics;
