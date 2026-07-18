alter table bmsql_warehouse add constraint bmsql_warehouse_pkey
  primary key (w_id) using index(create unique index warehouse_index on bmsql_warehouse(w_id) CRMODE PAGE LOCAL);

alter table bmsql_district add constraint bmsql_district_pkey
  primary key (d_w_id, d_id) using index(create unique index district_index on bmsql_district(d_w_id, d_id) CRMODE PAGE LOCAL);

alter table bmsql_customer add constraint bmsql_customer_pkey
  primary key (c_w_id, c_d_id, c_id) using index(create unique index customer_index on bmsql_customer(c_w_id, c_d_id, c_id) CRMODE PAGE LOCAL);

create index bmsql_customer_idx1
  on  bmsql_customer (c_w_id, c_d_id, c_last, c_first) CRMODE PAGE LOCAL;

alter table bmsql_oorder add constraint bmsql_oorder_pkey
  primary key (o_w_id, o_d_id, o_id) using index(create unique index oorder_index on bmsql_oorder(o_w_id, o_d_id, o_id) CRMODE PAGE LOCAL);

create unique index bmsql_oorder_idx1
  on  bmsql_oorder (o_w_id, o_d_id, o_c_id, o_id) CRMODE PAGE LOCAL;

alter table bmsql_new_order add constraint bmsql_new_order_pkey
  primary key (no_w_id, no_d_id, no_o_id) using index(create unique index new_order_index on bmsql_new_order(no_w_id, no_d_id, no_o_id) CRMODE PAGE LOCAL);

alter table bmsql_order_line add constraint bmsql_order_line_pkey
 primary key (ol_w_id, ol_d_id, ol_o_id, ol_number) using index(create unique index order_line_index on bmsql_order_line(ol_w_id, ol_d_id, ol_o_id, ol_number) CRMODE PAGE LOCAL);

alter table bmsql_stock add constraint bmsql_stock_pkey
  primary key (s_w_id, s_i_id) using index(create unique index stock_index on bmsql_stock(s_w_id, s_i_id) CRMODE PAGE LOCAL);

alter table bmsql_item add constraint bmsql_item_pkey
  primary key (i_id) using index(create unique index item_index on bmsql_item(i_id) CRMODE PAGE LOCAL);
