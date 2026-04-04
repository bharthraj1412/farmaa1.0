import httpx

try:
    print('Testing Production Vercel...')
    with httpx.Client(base_url='https://farmaa1-0.vercel.app', timeout=10.0) as client:
        # test crops
        r1 = client.get('/crops')
        print('/crops ->', r1.status_code)
        
        # test market
        r2 = client.get('/market')
        print('/market ->', r2.status_code)
        
        # test ai error ?
        r3 = client.post('/ai/chat', json={'messages': [{'role':'user','content':'hi'}]})
        print('/ai/chat ->', r3.status_code)
        if r3.status_code == 500:
            print('AI response:', r3.text)
            
except Exception as e:
    print('Failed:', e)
