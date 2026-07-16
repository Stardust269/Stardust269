# 标注及声明信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_mark_info)
page_id: 39c617cf-3593-8080-b906-cadcc83d155c


| 数值类型 | 字段解释 | 字段编码 | 字段名称 | 数据格式 |
| long | 自增主键ID | id | 主键ID |  |
| varchar(32) | 报告ID | id_unqf | 报告ID |  |
| varchar(32) | 客户ID | id_unqp | 客户ID |  |
| varchar(60) | 数据块标识 | common_data_block_type | 数据块类型 | 对应字典：mark_data_block_type |
| varchar(60) | 数据ID | data_id | 数据ID | 数据ID |
| varchar(8) | 标注及声明类型 | label_declare_type | 标注及声明类型 | 对应字典：label_declare_type_code |
| varchar(256) | 标注或声明内容 | label_content | 标注或声明内容 |  |
| date | 添加日期 | add_date | 数据添加日期 |  |
| datetime | 插入时间 | time_inst | 插入时间 |  |