import httpx

try:
    with httpx.Client(base_url='http://127.0.0.1:8000') as client:
        # get crop
        print('Testing /crops...')
        r = client.get('/crops')
        print(r.status_code, r.text)
        
        # Test an invalid token just to see if we hit orders with 401
        print('\nTesting /orders/...')
        r = client.post('/orders/', headers={'Authorization':'Bearer dummy'}, json={'crop_id':'test', 'quantity_kg':1})
        print(r.status_code, r.text)
except Exception as e:
    print('Failed:', e)
