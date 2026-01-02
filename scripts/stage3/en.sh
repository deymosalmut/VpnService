curl -s -i \
  http://localhost:5272/api/v1/admin/wg/state?iface=wg1 \
  -H "Authorization: Bearer $TOKEN"
