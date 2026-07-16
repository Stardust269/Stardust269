# 住房公积金参缴记录（lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record)
page_id: 39c617cf-3593-80d3-9142-faff91e9f7ea


| 备注 | 字段解释 | 数值类型 | 字段名称 | 字段编码 |
|  | 自增主键ID | long | 主键ID | id |
|  | 报告ID | varchar(32) | 报告ID | id_unqf |
|  | 客户ID | varchar(32) | 客户ID | id_unqp |
|  | 住房公积金参缴地 | varchar(50) | 住房公积金参缴地 | addh_reg |
|  | 住房公积金参缴日期 | date | 住房公积金参缴日期 | timeh_hf |
|  | 住房公积金初缴月份 | varchar(8) | 住房公积金初缴月份 | timeh_fstp |
|  | 住房公积金缴至月份 | varchar(8) | 住房公积金缴至月份 | timeh_lstp |
| 对应状态表：gjj_pay_status_code | 住房公积金缴费状态 | varchar(20) | 住房公积金缴费状态 | timeh_sts |
|  | 住房公积金月缴存额 | int | 住房公积金月缴存额 | amth_mp |
|  | 住房公积金个人缴存比例 | int | 住房公积金个人缴存比例 | pcth_indp |
|  | 住房公积金单位缴存比例 | int | 住房公积金单位缴存比例 | pcth_emp |
|  | 住房公积金缴费单位 | varchar(100) | 住房公积金缴费单位 | orgh |
|  | 住房公积金信息更新日期 | date | 住房公积金信息更新日期 | timeh_upd |
|  | 系统插入时间 | datetime | 系统插入时间 | time_inst |